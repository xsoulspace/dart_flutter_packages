import 'dart:async';

import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'decision_store.dart';
import 'kernel/migration_coordinator.dart';
import 'kernel/observation_hub.dart';
import 'kernel/outbox.dart';
import 'storage_profile_resolver.dart';
import 'sync_queue_store.dart';

/// Optional callback for custom conflict decision routing.
typedef ConflictDecisionHook =
    FutureOr<DecisionState> Function(SyncConflictEntry conflict);

/// Profile-aware storage kernel.
///
/// Thin facade over focused collaborators: [ObservationHub] for events,
/// [OutboxManager]/[OutboxReplayer] for durable replay, and
/// [MigrationCoordinator] for migration flows.
final class StorageKernel implements StorageKernelContract {
  StorageKernel({
    required this.profile,
    required StorageProfileResolver resolver,
    final SyncEngine? syncEngine,
    final MigrationEndpoint? migrationEndpoint,
    final DecisionStore? decisionStore,
    final SyncQueueStore? queueStore,
    final ConflictDecisionHook? conflictDecisionHook,
  }) : _resolver = resolver,
       _syncEngine = syncEngine,
       _decisionStore = decisionStore ?? InMemoryDecisionStore(),
       _queueStore = queueStore ?? StorageServiceSyncQueueStore(),
       _observations = ObservationHub() {
    _outbox = OutboxManager(
      queueStore: _queueStore,
      observations: _observations,
    );
    _replayer = OutboxReplayer(
      decisionStore: _decisionStore,
      observations: _observations,
      conflictDecisionHook: conflictDecisionHook,
    );
    _migration = MigrationCoordinator(
      endpoint: migrationEndpoint,
      decisionStore: _decisionStore,
      observations: _observations,
    );
  }

  final StorageProfile profile;
  final StorageProfileResolver _resolver;
  final SyncEngine? _syncEngine;
  final DecisionStore _decisionStore;
  final SyncQueueStore _queueStore;
  final ObservationHub _observations;

  late final OutboxManager _outbox;
  late final OutboxReplayer _replayer;
  late final MigrationCoordinator _migration;

  final Map<StorageNamespace, String> _interactionDowngradeReasons =
      <StorageNamespace, String>{};

  /// Returns recorded downgrade reason if `complex` interaction was requested
  /// but unsupported.
  String? interactionDowngradeReasonFor(final StorageNamespace namespace) =>
      _interactionDowngradeReasons[namespace];

  /// Resolves active interaction level with capability-aware degrade.
  Future<SyncInteractionLevel> resolveInteractionLevel(
    final StorageNamespace namespace,
  ) async {
    final namespaceProfile = profile.namespaceProfile(namespace);
    final requested = namespaceProfile.syncInteractionLevel;
    final available = await _resolver.resolveCapabilities(namespace);
    final resolved = namespaceProfile.resolveInteractionLevel(available);

    if (requested == SyncInteractionLevel.complex &&
        resolved == SyncInteractionLevel.minimal) {
      _interactionDowngradeReasons[namespace] =
          'Complex mode requested but capabilities are insufficient.';
    } else {
      _interactionDowngradeReasons.remove(namespace);
    }

    return resolved;
  }

  /// Builds object path for namespace based on profile prefix and extension.
  String pathForObject({
    required final StorageNamespace namespace,
    required final StorageObjectId objectId,
  }) {
    final namespaceProfile = profile.namespaceProfile(namespace);
    final prefix = namespaceProfile.pathPrefix.trim();
    final rawExt = namespaceProfile.defaultFileExtension.trim();
    final ext = rawExt.isEmpty
        ? ''
        : rawExt.startsWith('.')
        ? rawExt
        : '.$rawExt';

    final base = '$prefix/${objectId.value}$ext'
        .replaceAll(RegExp('/+'), '/')
        .replaceFirst(RegExp('^/'), '');
    return base;
  }

  Future<String?> readObject({
    required final StorageNamespace namespace,
    required final StorageObjectId objectId,
  }) => read(
    namespace: namespace,
    path: pathForObject(namespace: namespace, objectId: objectId),
  );

  Future<FileOperationResult> writeObject({
    required final StorageNamespace namespace,
    required final StorageObjectId objectId,
    required final String content,
    final String? message,
  }) => write(
    namespace: namespace,
    path: pathForObject(namespace: namespace, objectId: objectId),
    content: content,
    message: message,
  );

  @override
  Future<String?> read({
    required final StorageNamespace namespace,
    required final String path,
  }) async {
    final service = await _resolver.resolveService(namespace);
    return service.readFile(path);
  }

  @override
  Future<FileOperationResult> write({
    required final StorageNamespace namespace,
    required final String path,
    required final String content,
    final String? message,
  }) async {
    final namespaceProfile = profile.namespaceProfile(namespace);
    final service = await _resolver.resolveService(namespace);
    final result = await service.saveFile(path, content, message: message);
    String? queueEntryId;
    if (namespaceProfile.requiresRemote) {
      queueEntryId = await _outbox.enqueue(
        namespaceProfile: namespaceProfile,
        service: service,
        operation: SyncQueueOperationType.write,
        path: result.path,
        content: content,
        message: message,
        result: result,
      );
    }

    final operationMetadata = <String, dynamic>{
      if (result.revisionId.isNotEmpty) 'revision_id': result.revisionId,
      if (result.metadata.isNotEmpty) ...result.metadata,
      'outbox_entry_id': ?queueEntryId,
    };
    _observations.emit(
      type: result.isNew
          ? StorageObservationType.created
          : StorageObservationType.updated,
      namespace: namespace,
      path: result.path,
      origin: StorageOperationOrigin.local,
      metadata: operationMetadata,
    );
    return result;
  }

  @override
  Future<FileOperationResult> delete({
    required final StorageNamespace namespace,
    required final String path,
    final String? message,
  }) async {
    final namespaceProfile = profile.namespaceProfile(namespace);
    final service = await _resolver.resolveService(namespace);
    final result = await service.removeFile(path, message: message);
    String? queueEntryId;
    if (namespaceProfile.requiresRemote) {
      queueEntryId = await _outbox.enqueue(
        namespaceProfile: namespaceProfile,
        service: service,
        operation: SyncQueueOperationType.delete,
        path: result.path,
        content: '',
        message: message,
        result: result,
      );
    }

    final operationMetadata = <String, dynamic>{
      if (result.revisionId.isNotEmpty) 'revision_id': result.revisionId,
      if (result.metadata.isNotEmpty) ...result.metadata,
      'outbox_entry_id': ?queueEntryId,
    };
    _observations.emit(
      type: StorageObservationType.deleted,
      namespace: namespace,
      path: result.path,
      origin: StorageOperationOrigin.local,
      metadata: operationMetadata,
    );
    return result;
  }

  @override
  Future<List<FileEntry>> list({
    required final StorageNamespace namespace,
    final String directoryPath = '.',
  }) async {
    final service = await _resolver.resolveService(namespace);
    return service.listDirectory(directoryPath);
  }

  @override
  Stream<StorageObservationEvent> observe({
    final StorageNamespace? namespace,
    final String? pathPrefix,
  }) => _observations.observe(namespace: namespace, pathPrefix: pathPrefix);

  /// Returns outbox snapshot for [namespace].
  Future<List<SyncOutboxEntry>> outboxSnapshot(
    final StorageNamespace namespace,
  ) async {
    final service = await _resolver.resolveService(namespace);
    return _outbox.snapshot(namespace, service: service);
  }

  /// Returns dead-letter snapshot for [namespace].
  Future<List<SyncOutboxEntry>> deadLetterSnapshot(
    final StorageNamespace namespace,
  ) async {
    final service = await _resolver.resolveService(namespace);
    return _outbox.deadLetterSnapshot(namespace, service: service);
  }

  /// Returns staged conflict snapshot for [namespace].
  Future<List<SyncConflictEntry>> conflictSnapshot(
    final StorageNamespace namespace,
  ) async {
    final service = await _resolver.resolveService(namespace);
    final state = await _queueStore.loadState(
      namespace: namespace,
      service: service,
    );
    return List<SyncConflictEntry>.unmodifiable(state.conflicts);
  }

  @override
  Future<void> sync({final StorageNamespace? namespace}) async {
    final namespaceProfiles = namespace == null
        ? profile.namespaces
        : <StorageNamespaceProfile>[profile.namespaceProfile(namespace)];

    for (final namespaceProfile in namespaceProfiles) {
      if (namespaceProfile.policy == StoragePolicy.localOnly) {
        _observations.emit(
          type: StorageObservationType.syncSkipped,
          namespace: namespaceProfile.namespace,
          path: '',
          metadata: const <String, dynamic>{'reason': 'policy_local_only'},
        );
        continue;
      }

      final interactionLevel = await resolveInteractionLevel(
        namespaceProfile.namespace,
      );
      final service = await _resolver.resolveService(
        namespaceProfile.namespace,
      );
      final queueState = await _queueStore.loadState(
        namespace: namespaceProfile.namespace,
        service: service,
      );

      final report = await _replayer.run(
        namespaceProfile: namespaceProfile,
        interactionLevel: interactionLevel,
        service: service,
        queueState: queueState,
        performSync: () => _performNamespaceSync(
          namespaceProfile: namespaceProfile,
          service: service,
        ),
      );

      await _queueStore.saveState(
        namespace: namespaceProfile.namespace,
        service: service,
        state: report.queueState,
      );

      _observations.emit(
        type: StorageObservationType.synced,
        namespace: namespaceProfile.namespace,
        path: '',
        result: report.result,
        metadata: <String, dynamic>{
          'outbox_pending': report.queueState.outbox.length,
          'dead_letter': report.queueState.deadLetter.length,
          'conflicts': report.queueState.conflicts.length,
          'replayed_entries': report.replayedEntries,
          'dead_lettered_entries': report.deadLetteredEntries,
          'staged_conflicts': report.stagedConflicts,
          if (interactionDowngradeReasonFor(namespaceProfile.namespace) != null)
            'interaction_downgrade_reason': interactionDowngradeReasonFor(
              namespaceProfile.namespace,
            ),
          ...report.metadata,
        },
      );
    }
  }

  @override
  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  }) => _migration.prepare(plan: plan);

  @override
  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  }) => _migration.execute(plan: plan);

  @override
  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  }) => _migration.rollback(plan: plan);

  @override
  Future<StorageOperationResult> resolveDecision({
    required final StorageDecision decision,
    required final DecisionState targetState,
    final String note = '',
  }) async {
    await _decisionStore.saveState(
      decisionId: decision.id,
      state: targetState,
      note: note,
    );

    await applyDecisionToQueues(
      decisionStore: _decisionStore,
      queueStore: _queueStore,
      observations: _observations,
      resolver: _resolver,
      decision: decision,
      targetState: targetState,
      note: note,
    );

    final result = StorageOperationResult.success(
      message: 'Decision updated.',
      metadata: <String, dynamic>{
        'decision_id': decision.id,
        'namespace': decision.namespace.value,
        'target_state': targetState.name,
        if (note.isNotEmpty) 'note': note,
      },
    );
    _observations.emit(
      type: StorageObservationType.decisionResolved,
      namespace: decision.namespace,
      path: '',
      result: result,
      metadata: <String, dynamic>{
        'decision_id': decision.id,
        'target_state': targetState.name,
      },
    );
    return result;
  }

  /// Returns persisted state for [decisionId] if available.
  Future<DecisionState?> decisionState(final String decisionId) =>
      _decisionStore.loadState(decisionId);

  /// Returns a snapshot of all persisted decision states.
  Future<Map<String, DecisionState>> decisionStatesSnapshot() =>
      _decisionStore.loadAllStates();

  Future<StorageOperationResult> _performNamespaceSync({
    required final StorageNamespaceProfile namespaceProfile,
    required final StorageService service,
  }) async {
    if (_syncEngine != null) {
      return _syncEngine.syncNamespace(
        namespaceProfile: namespaceProfile,
        service: service,
      );
    }

    await service.syncRemote(
      pullMergeStrategy: pullMergeStrategyFor(
        namespaceProfile.conflictResolution,
      ),
      pushConflictStrategy: pushConflictStrategyFor(
        namespaceProfile.conflictResolution,
      ),
    );

    return StorageOperationResult.success(
      message: 'Sync completed using provider syncRemote.',
      metadata: <String, dynamic>{
        'pull_merge_strategy': pullMergeStrategyFor(
          namespaceProfile.conflictResolution,
        ),
        'push_conflict_strategy': pushConflictStrategyFor(
          namespaceProfile.conflictResolution,
        ),
      },
    );
  }

  /// Closes kernel observation streams.
  Future<void> dispose() => _observations.close();
}

/// Maps conflict resolution strategy to provider pull/merge strategy.
String pullMergeStrategyFor(
  final ConflictResolutionStrategy conflictResolution,
) => switch (conflictResolution) {
  ConflictResolutionStrategy.clientAlwaysRight => 'rebase',
  ConflictResolutionStrategy.serverAlwaysRight => 'merge',
  ConflictResolutionStrategy.manualResolution => 'ff-only',
  ConflictResolutionStrategy.lastWriteWins => 'merge',
};

/// Maps conflict resolution strategy to provider push conflict strategy.
String pushConflictStrategyFor(
  final ConflictResolutionStrategy conflictResolution,
) => switch (conflictResolution) {
  ConflictResolutionStrategy.clientAlwaysRight => 'rebase-local',
  ConflictResolutionStrategy.serverAlwaysRight => 'fail-on-conflict',
  ConflictResolutionStrategy.manualResolution => 'fail-on-conflict',
  ConflictResolutionStrategy.lastWriteWins => 'force-with-lease',
};
