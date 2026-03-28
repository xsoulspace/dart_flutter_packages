import 'dart:async';
import 'dart:convert';

import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'decision_store.dart';
import 'storage_profile_resolver.dart';
import 'sync_queue_store.dart';

/// Optional callback for custom conflict decision routing.
typedef ConflictDecisionHook =
    FutureOr<DecisionState> Function(SyncConflictEntry conflict);

/// Profile-aware storage kernel.
final class StorageKernel implements StorageKernelContract {
  StorageKernel({
    required this.profile,
    required final StorageProfileResolver resolver,
    final SyncEngine? syncEngine,
    final MigrationEndpoint? migrationEndpoint,
    final DecisionStore? decisionStore,
    final SyncQueueStore? queueStore,
    final ConflictDecisionHook? conflictDecisionHook,
  }) : _resolver = resolver,
       _syncEngine = syncEngine,
       _migrationEndpoint = migrationEndpoint,
       _decisionStore = decisionStore ?? InMemoryDecisionStore(),
       _queueStore = queueStore ?? StorageServiceSyncQueueStore(),
       _conflictDecisionHook = conflictDecisionHook;

  final StorageProfile profile;
  final StorageProfileResolver _resolver;
  final SyncEngine? _syncEngine;
  final MigrationEndpoint? _migrationEndpoint;
  final DecisionStore _decisionStore;
  final SyncQueueStore _queueStore;
  final ConflictDecisionHook? _conflictDecisionHook;

  final Map<String, DecisionState> _decisionStates = <String, DecisionState>{};
  final Map<StorageNamespace, String> _interactionDowngradeReasons =
      <StorageNamespace, String>{};
  final StreamController<StorageObservationEvent> _eventsController =
      StreamController<StorageObservationEvent>.broadcast(sync: true);
  int _observationSequence = 0;

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
      queueEntryId = await _enqueueOutboxEntry(
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
      if (queueEntryId != null) 'outbox_entry_id': queueEntryId,
    };
    _emitObservation(
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
      queueEntryId = await _enqueueOutboxEntry(
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
      if (queueEntryId != null) 'outbox_entry_id': queueEntryId,
    };
    _emitObservation(
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
  }) {
    final normalizedPrefix = (pathPrefix ?? '').trim();

    return _eventsController.stream.where((final event) {
      if (namespace != null && event.namespace != namespace) {
        return false;
      }
      if (normalizedPrefix.isNotEmpty &&
          !event.path.startsWith(normalizedPrefix)) {
        return false;
      }
      return true;
    });
  }

  /// Returns outbox snapshot for [namespace].
  Future<List<SyncOutboxEntry>> outboxSnapshot(
    final StorageNamespace namespace,
  ) async {
    final service = await _resolver.resolveService(namespace);
    final state = await _queueStore.loadState(
      namespace: namespace,
      service: service,
    );
    return List<SyncOutboxEntry>.unmodifiable(state.outbox);
  }

  /// Returns dead-letter snapshot for [namespace].
  Future<List<SyncOutboxEntry>> deadLetterSnapshot(
    final StorageNamespace namespace,
  ) async {
    final service = await _resolver.resolveService(namespace);
    final state = await _queueStore.loadState(
      namespace: namespace,
      service: service,
    );
    return List<SyncOutboxEntry>.unmodifiable(state.deadLetter);
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
        _emitObservation(
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

      final report = await _syncNamespaceWithQueue(
        namespaceProfile: namespaceProfile,
        interactionLevel: interactionLevel,
        service: service,
        queueState: queueState,
      );

      await _queueStore.saveState(
        namespace: namespaceProfile.namespace,
        service: service,
        state: report.queueState,
      );

      _emitObservation(
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
  }) async {
    MigrationPreparationResult result;
    if (_migrationEndpoint != null) {
      result = await _migrationEndpoint.prepareMigration(plan: plan);
      _emitObservation(
        type: StorageObservationType.migrationPrepared,
        namespace: StorageNamespace.settings,
        path: '',
        result: result.ok
            ? StorageOperationResult.success(
                message: _preparationMessageFor(result),
              )
            : StorageOperationResult.failure(
                message: _preparationMessageFor(result),
              ),
        metadata: <String, dynamic>{
          'plan_id': plan.id,
          'status': plan.status.name,
        },
      );
      return result;
    }

    final issues = <String>[];
    final warnings = <String>[];

    if (plan.id.isEmpty) {
      issues.add('Migration id is empty.');
    }
    if (plan.sourceProfileHash.isEmpty || plan.targetProfileHash.isEmpty) {
      issues.add('Source/target profile hashes must be provided.');
    }
    if (plan.sourceProfileHash == plan.targetProfileHash) {
      warnings.add('Source and target profile hash are identical.');
    }

    result = MigrationPreparationResult(
      ok: issues.isEmpty,
      issues: issues,
      warnings: warnings,
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': plan.status.name,
      },
    );

    _emitObservation(
      type: StorageObservationType.migrationPrepared,
      namespace: StorageNamespace.settings,
      path: '',
      result: result.ok
          ? StorageOperationResult.success(
              message: _preparationMessageFor(result),
            )
          : StorageOperationResult.failure(
              message: _preparationMessageFor(result),
            ),
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': plan.status.name,
      },
    );

    return result;
  }

  @override
  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  }) async {
    MigrationExecutionResult executionResult;
    if (_migrationEndpoint != null) {
      final decisionStates = await _decisionStore.loadAllStates();
      final pauseForDecisions =
          _migrationPlanBool(plan.metadata, 'pause_for_decisions') ??
          _migrationPlanInteractionLevel(plan.metadata);
      final collectDiffs =
          _migrationPlanBool(plan.metadata, 'collect_diffs') ??
          pauseForDecisions;
      final overwrite = _migrationPlanBool(plan.metadata, 'overwrite') ?? true;
      final dryRun = _migrationPlanBool(plan.metadata, 'dry_run') ?? false;

      executionResult = await _migrationEndpoint.executeMigrationWithOptions(
        plan: plan,
        overwrite: overwrite,
        dryRun: dryRun,
        collectDiffs: collectDiffs,
        pauseForDecisions: pauseForDecisions,
        decisionStates: decisionStates,
      );
      _emitObservation(
        type: StorageObservationType.migrationExecuted,
        namespace: StorageNamespace.settings,
        path: '',
        result: executionResult.ok
            ? StorageOperationResult.success(message: executionResult.message)
            : StorageOperationResult.failure(message: executionResult.message),
        metadata: <String, dynamic>{
          'plan_id': plan.id,
          'status': executionResult.status.name,
        },
      );
      return executionResult;
    }

    final preparation = await prepareMigration(plan: plan);
    if (!preparation.ok) {
      executionResult = MigrationExecutionResult(
        ok: false,
        status: MigrationStatus.failed,
        message: 'Migration preflight failed.',
        metadata: <String, dynamic>{
          'issues': preparation.issues,
          'warnings': preparation.warnings,
        },
      );
      _emitObservation(
        type: StorageObservationType.migrationExecuted,
        namespace: StorageNamespace.settings,
        path: '',
        result: StorageOperationResult.failure(
          message: executionResult.message,
        ),
        metadata: <String, dynamic>{
          'plan_id': plan.id,
          'status': executionResult.status.name,
        },
      );
      return executionResult;
    }

    executionResult = const MigrationExecutionResult(
      ok: false,
      status: MigrationStatus.failed,
      message:
          'No migration endpoint configured. Provide MigrationEndpoint to execute migration.',
    );
    _emitObservation(
      type: StorageObservationType.migrationExecuted,
      namespace: StorageNamespace.settings,
      path: '',
      result: StorageOperationResult.failure(message: executionResult.message),
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': executionResult.status.name,
      },
    );
    return executionResult;
  }

  bool _migrationPlanInteractionLevel(final Map<String, dynamic> metadata) {
    final rawLevel = metadata['migration_interaction_level'];
    return rawLevel is String &&
        rawLevel.trim().toLowerCase() == SyncInteractionLevel.complex.name;
  }

  bool? _migrationPlanBool(
    final Map<String, dynamic> metadata,
    final String key,
  ) {
    final raw = metadata[key];
    if (raw == null) {
      return null;
    }
    if (raw is bool) {
      return raw;
    }
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'y') {
        return true;
      }
      if (normalized == '0' ||
          normalized == 'false' ||
          normalized == 'no' ||
          normalized == 'n') {
        return false;
      }
      return null;
    }
    if (raw is num) {
      return raw > 0;
    }
    return null;
  }

  @override
  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  }) async {
    if (_migrationEndpoint == null) {
      const executionResult = MigrationExecutionResult(
        ok: false,
        status: MigrationStatus.failed,
        message:
            'No migration endpoint configured. Provide MigrationEndpoint to rollback migration.',
      );
      _emitObservation(
        type: StorageObservationType.migrationExecuted,
        namespace: StorageNamespace.settings,
        path: '',
        result: StorageOperationResult.failure(
          message: executionResult.message,
        ),
        metadata: <String, dynamic>{
          'plan_id': plan.id,
          'status': executionResult.status.name,
        },
      );
      return executionResult;
    }

    final executionResult = await _migrationEndpoint.rollbackMigration(
      plan: plan,
    );
    _emitObservation(
      type: StorageObservationType.migrationExecuted,
      namespace: StorageNamespace.settings,
      path: '',
      result: executionResult.ok
          ? StorageOperationResult.success(message: executionResult.message)
          : StorageOperationResult.failure(message: executionResult.message),
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': executionResult.status.name,
      },
    );
    return executionResult;
  }

  @override
  Future<StorageOperationResult> resolveDecision({
    required final StorageDecision decision,
    required final DecisionState targetState,
    final String note = '',
  }) async {
    _decisionStates[decision.id] = targetState;
    await _decisionStore.saveState(
      decisionId: decision.id,
      state: targetState,
      note: note,
    );

    await _applyDecisionToConflictQueue(
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
    _emitObservation(
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

  Future<String?> _enqueueOutboxEntry({
    required final StorageNamespaceProfile namespaceProfile,
    required final StorageService service,
    required final SyncQueueOperationType operation,
    required final String path,
    required final String content,
    required final String? message,
    required final FileOperationResult result,
  }) async {
    final now = DateTime.now().toUtc();
    final queueState = await _queueStore.loadState(
      namespace: namespaceProfile.namespace,
      service: service,
    );

    final contentDigest = operation == SyncQueueOperationType.write
        ? _hashString(content)
        : '';
    final operationSeed = operation == SyncQueueOperationType.write
        ? (result.revisionId.isNotEmpty ? result.revisionId : contentDigest)
        : path;

    final entryId = _deterministicEntryId(
      namespace: namespaceProfile.namespace,
      operation: operation,
      path: path,
      seed: operationSeed,
    );

    final metadata = <String, dynamic>{
      if (result.revisionId.isNotEmpty) 'revision_id': result.revisionId,
      if (result.metadata.isNotEmpty) ...result.metadata,
    };

    final newEntry = SyncOutboxEntry(
      id: entryId,
      namespace: namespaceProfile.namespace,
      operation: operation,
      path: path,
      createdAtUtc: now,
      updatedAtUtc: now,
      message: message ?? '',
      contentDigest: contentDigest,
      localRevisionId: result.revisionId,
      metadata: metadata,
    );

    final nextOutbox = <SyncOutboxEntry>[
      for (final entry in queueState.outbox)
        if (entry.id != newEntry.id &&
            !(entry.path == newEntry.path && entry.operation == operation))
          entry,
      newEntry,
    ]..sort((final a, final b) => a.createdAtUtc.compareTo(b.createdAtUtc));

    final nextState = queueState.copyWith(outbox: nextOutbox);
    await _queueStore.saveState(
      namespace: namespaceProfile.namespace,
      service: service,
      state: nextState,
    );

    _emitObservation(
      type: StorageObservationType.outboxQueued,
      namespace: namespaceProfile.namespace,
      path: path,
      origin: StorageOperationOrigin.local,
      metadata: <String, dynamic>{
        'outbox_entry_id': entryId,
        'operation': operation.name,
        'outbox_pending': nextOutbox.length,
      },
    );

    return entryId;
  }

  Future<_NamespaceSyncReport> _syncNamespaceWithQueue({
    required final StorageNamespaceProfile namespaceProfile,
    required final SyncInteractionLevel interactionLevel,
    required final StorageService service,
    required final SyncQueueState queueState,
  }) async {
    final now = DateTime.now().toUtc();
    final queuePolicy = namespaceProfile.queuePolicy;

    var outbox = <SyncOutboxEntry>[];
    final deadLetter = List<SyncOutboxEntry>.from(queueState.deadLetter);
    var conflicts = List<SyncConflictEntry>.from(queueState.conflicts);
    final appliedEntryIds = _uniqueStrings(queueState.appliedEntryIds);

    var deadLetteredEntries = 0;
    for (final entry in queueState.outbox) {
      if (appliedEntryIds.contains(entry.id)) {
        continue;
      }
      if (queuePolicy.exceedsMaxAge(
        createdAtUtc: entry.createdAtUtc,
        nowUtc: now,
      )) {
        final deadEntry = entry.copyWith(
          updatedAtUtc: now,
          lastError: entry.lastError.isEmpty
              ? 'Entry exceeded max age policy.'
              : entry.lastError,
        );
        deadLetter.add(deadEntry);
        deadLetteredEntries++;
        _emitObservation(
          type: StorageObservationType.outboxDeadLettered,
          namespace: namespaceProfile.namespace,
          path: entry.path,
          metadata: <String, dynamic>{
            'outbox_entry_id': entry.id,
            'reason': 'max_age_exceeded',
          },
        );
        continue;
      }
      outbox.add(entry);
    }

    outbox.sort((final a, final b) => a.createdAtUtc.compareTo(b.createdAtUtc));

    final dueEntries = outbox
        .where(
          (final entry) =>
              entry.nextAttemptAtUtc == null ||
              !entry.nextAttemptAtUtc!.isAfter(now),
        )
        .toList(growable: false);

    StorageOperationResult syncResult;
    var replayedEntries = 0;
    var stagedConflicts = 0;
    var metadata = const <String, dynamic>{};

    try {
      final providerSyncResult = await _performNamespaceSync(
        namespaceProfile: namespaceProfile,
        service: service,
      );
      syncResult = providerSyncResult;
      metadata = providerSyncResult.metadata;

      if (dueEntries.isNotEmpty) {
        final replayedIds = dueEntries.map((final item) => item.id).toSet();
        outbox = outbox
            .where((final entry) => !replayedIds.contains(entry.id))
            .toList(growable: false);

        for (final replayed in dueEntries) {
          if (!appliedEntryIds.contains(replayed.id)) {
            appliedEntryIds.add(replayed.id);
          }
          replayedEntries++;
          _emitObservation(
            type: StorageObservationType.outboxReplayed,
            namespace: namespaceProfile.namespace,
            path: replayed.path,
            origin: StorageOperationOrigin.remote,
            metadata: <String, dynamic>{
              'outbox_entry_id': replayed.id,
              'operation': replayed.operation.name,
            },
          );
        }
      }
    } on Object catch (error) {
      final message = _errorMessage(error);
      final isConflict = _isConflictError(error);
      final dueIds = dueEntries.map((final entry) => entry.id).toSet();
      final nextOutbox = <SyncOutboxEntry>[];

      for (final entry in outbox) {
        if (!dueIds.contains(entry.id)) {
          nextOutbox.add(entry);
          continue;
        }

        final updatedAttempts = entry.attempts + 1;
        final updatedEntry = entry.copyWith(
          updatedAtUtc: now,
          attempts: updatedAttempts,
          nextAttemptAtUtc: now.add(
            queuePolicy.backoffForAttempt(updatedAttempts),
          ),
          lastError: message,
        );

        var shouldDeadLetter = updatedAttempts >= queuePolicy.maxRetries;
        if (queuePolicy.exceedsMaxAge(
          createdAtUtc: updatedEntry.createdAtUtc,
          nowUtc: now,
        )) {
          shouldDeadLetter = true;
        }

        if (isConflict) {
          final conflictState = await _stageConflict(
            namespaceProfile: namespaceProfile,
            interactionLevel: interactionLevel,
            outboxEntry: updatedEntry,
            reason: message,
            existingConflicts: conflicts,
          );
          conflicts = conflictState.conflicts;
          stagedConflicts += conflictState.stagedCount;

          if (conflictState.decisionState == DecisionState.blocked) {
            shouldDeadLetter = true;
          }
        }

        if (shouldDeadLetter) {
          deadLetter.add(updatedEntry);
          deadLetteredEntries++;
          _emitObservation(
            type: StorageObservationType.outboxDeadLettered,
            namespace: namespaceProfile.namespace,
            path: updatedEntry.path,
            metadata: <String, dynamic>{
              'outbox_entry_id': updatedEntry.id,
              'reason': isConflict ? 'conflict_or_retry_limit' : 'retry_limit',
              'attempts': updatedEntry.attempts,
            },
          );
        } else {
          nextOutbox.add(updatedEntry);
        }
      }

      outbox = nextOutbox;

      syncResult = StorageOperationResult.failure(
        message: message,
        decisionState: isConflict
            ? DecisionState.needsUserDecision
            : DecisionState.blocked,
        metadata: <String, dynamic>{
          'error_type': error.runtimeType.toString(),
          if (isConflict) 'conflict': true,
        },
      );
      metadata = syncResult.metadata;
    }

    return _NamespaceSyncReport(
      queueState: SyncQueueState(
        outbox: List<SyncOutboxEntry>.unmodifiable(outbox),
        deadLetter: List<SyncOutboxEntry>.unmodifiable(deadLetter),
        conflicts: List<SyncConflictEntry>.unmodifiable(conflicts),
        appliedEntryIds: List<String>.unmodifiable(appliedEntryIds),
      ),
      result: syncResult,
      replayedEntries: replayedEntries,
      deadLetteredEntries: deadLetteredEntries,
      stagedConflicts: stagedConflicts,
      metadata: metadata,
    );
  }

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
      pullMergeStrategy: _pullMergeStrategyFor(
        namespaceProfile.conflictResolution,
      ),
      pushConflictStrategy: _pushConflictStrategyFor(
        namespaceProfile.conflictResolution,
      ),
    );

    return StorageOperationResult.success(
      message: 'Sync completed using provider syncRemote.',
      metadata: <String, dynamic>{
        'pull_merge_strategy': _pullMergeStrategyFor(
          namespaceProfile.conflictResolution,
        ),
        'push_conflict_strategy': _pushConflictStrategyFor(
          namespaceProfile.conflictResolution,
        ),
      },
    );
  }

  Future<void> _applyDecisionToConflictQueue({
    required final StorageDecision decision,
    required final DecisionState targetState,
    required final String note,
  }) async {
    final conflictEntryId = decision.metadata['conflict_entry_id']?.toString();
    final outboxEntryId = decision.metadata['outbox_entry_id']?.toString();

    if ((conflictEntryId == null || conflictEntryId.isEmpty) &&
        (outboxEntryId == null || outboxEntryId.isEmpty)) {
      return;
    }

    final service = await _resolver.resolveService(decision.namespace);
    final currentState = await _queueStore.loadState(
      namespace: decision.namespace,
      service: service,
    );

    var conflicts = List<SyncConflictEntry>.from(currentState.conflicts);
    final outbox = List<SyncOutboxEntry>.from(currentState.outbox);
    final deadLetter = List<SyncOutboxEntry>.from(currentState.deadLetter);

    if (conflictEntryId != null && conflictEntryId.isNotEmpty) {
      conflicts = conflicts
          .map(
            (final entry) => entry.id == conflictEntryId
                ? entry.copyWith(
                    decisionState: targetState,
                    updatedAtUtc: DateTime.now().toUtc(),
                    metadata: <String, dynamic>{
                      ...entry.metadata,
                      if (note.isNotEmpty) 'decision_note': note,
                    },
                  )
                : entry,
          )
          .toList(growable: false);

      if (targetState != DecisionState.needsUserDecision) {
        conflicts = conflicts
            .where((final entry) => entry.id != conflictEntryId)
            .toList(growable: false);
      }
    }

    if (outboxEntryId != null && outboxEntryId.isNotEmpty) {
      final entryIndex = outbox.indexWhere(
        (final entry) => entry.id == outboxEntryId,
      );
      if (entryIndex >= 0) {
        final entry = outbox[entryIndex];
        if (targetState == DecisionState.blocked) {
          outbox.removeAt(entryIndex);
          deadLetter.add(
            entry.copyWith(
              updatedAtUtc: DateTime.now().toUtc(),
              lastError: note.isEmpty ? 'Blocked by user decision.' : note,
            ),
          );
          _emitObservation(
            type: StorageObservationType.outboxDeadLettered,
            namespace: decision.namespace,
            path: entry.path,
            metadata: <String, dynamic>{
              'outbox_entry_id': entry.id,
              'reason': 'decision_blocked',
            },
          );
        } else if (targetState == DecisionState.autoResolved) {
          outbox[entryIndex] = entry.copyWith(
            updatedAtUtc: DateTime.now().toUtc(),
            nextAttemptAtUtc: DateTime.now().toUtc(),
            lastError: '',
          );
        }
      }
    }

    await _queueStore.saveState(
      namespace: decision.namespace,
      service: service,
      state: currentState.copyWith(
        outbox: outbox,
        deadLetter: deadLetter,
        conflicts: conflicts,
      ),
    );
  }

  Future<_ConflictStageResult> _stageConflict({
    required final StorageNamespaceProfile namespaceProfile,
    required final SyncInteractionLevel interactionLevel,
    required final SyncOutboxEntry outboxEntry,
    required final String reason,
    required final List<SyncConflictEntry> existingConflicts,
  }) async {
    final now = DateTime.now().toUtc();
    final conflictId = 'conflict_${outboxEntry.id}';

    var decisionState = DecisionState.needsUserDecision;
    var stagedCount = 0;

    SyncConflictEntry conflict = SyncConflictEntry(
      id: conflictId,
      namespace: namespaceProfile.namespace,
      outboxEntryId: outboxEntry.id,
      path: outboxEntry.path,
      reason: reason,
      decisionState: decisionState,
      createdAtUtc: now,
      updatedAtUtc: now,
      metadata: <String, dynamic>{
        'operation': outboxEntry.operation.name,
        'attempts': outboxEntry.attempts,
      },
    );

    final hook = _conflictDecisionHook;
    if (hook != null) {
      decisionState = await hook(conflict);
      conflict = conflict.copyWith(decisionState: decisionState);
    } else if (interactionLevel == SyncInteractionLevel.minimal) {
      decisionState = DecisionState.needsUserDecision;
      conflict = conflict.copyWith(decisionState: decisionState);
    }

    final decisionId = 'decision_$conflictId';
    _decisionStates[decisionId] = decisionState;
    await _decisionStore.saveState(
      decisionId: decisionId,
      state: decisionState,
      note: reason,
    );

    final conflictIndex = existingConflicts.indexWhere(
      (final item) => item.id == conflict.id,
    );
    final nextConflicts = List<SyncConflictEntry>.from(existingConflicts);
    if (conflictIndex >= 0) {
      final existing = nextConflicts[conflictIndex];
      nextConflicts[conflictIndex] = existing.copyWith(
        reason: reason,
        decisionState: decisionState,
        updatedAtUtc: now,
        metadata: <String, dynamic>{
          ...existing.metadata,
          ...conflict.metadata,
          'attempts': outboxEntry.attempts,
        },
      );
    } else {
      nextConflicts.add(conflict);
      stagedCount = 1;
      _emitObservation(
        type: StorageObservationType.conflictStaged,
        namespace: namespaceProfile.namespace,
        path: outboxEntry.path,
        metadata: <String, dynamic>{
          'conflict_entry_id': conflict.id,
          'outbox_entry_id': outboxEntry.id,
          'decision_id': decisionId,
          'decision_state': decisionState.name,
        },
      );
    }

    return _ConflictStageResult(
      conflicts: nextConflicts,
      stagedCount: stagedCount,
      decisionState: decisionState,
    );
  }

  String _pullMergeStrategyFor(
    final ConflictResolutionStrategy conflictResolution,
  ) => switch (conflictResolution) {
    ConflictResolutionStrategy.clientAlwaysRight => 'rebase',
    ConflictResolutionStrategy.serverAlwaysRight => 'merge',
    ConflictResolutionStrategy.manualResolution => 'ff-only',
    ConflictResolutionStrategy.lastWriteWins => 'merge',
  };

  String _pushConflictStrategyFor(
    final ConflictResolutionStrategy conflictResolution,
  ) => switch (conflictResolution) {
    ConflictResolutionStrategy.clientAlwaysRight => 'rebase-local',
    ConflictResolutionStrategy.serverAlwaysRight => 'fail-on-conflict',
    ConflictResolutionStrategy.manualResolution => 'fail-on-conflict',
    ConflictResolutionStrategy.lastWriteWins => 'force-with-lease',
  };

  bool _isConflictError(final Object error) =>
      error is SyncConflictException ||
      error is GitConflictException ||
      error is MergeConflictException ||
      error is DecisionRequiredException;

  String _errorMessage(final Object error) {
    if (error is StorageException) {
      return error.message;
    }
    return error.toString();
  }

  List<String> _uniqueStrings(final List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (value.isEmpty || !seen.add(value)) {
        continue;
      }
      result.add(value);
    }
    return result;
  }

  String _deterministicEntryId({
    required final StorageNamespace namespace,
    required final SyncQueueOperationType operation,
    required final String path,
    required final String seed,
  }) {
    final raw = '${namespace.value}|${operation.name}|$path|$seed';
    return _hashString(raw);
  }

  String _hashString(final String value) {
    final mask64 = BigInt.parse('ffffffffffffffff', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);

    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask64;
    }

    return hash.toRadixString(16).padLeft(16, '0');
  }

  void _emitObservation({
    required final StorageObservationType type,
    required final StorageNamespace namespace,
    required final String path,
    final StorageOperationOrigin origin = StorageOperationOrigin.system,
    final StorageOperationResult? result,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    if (_eventsController.isClosed) {
      return;
    }

    final requestedCorrelationId =
        metadata['correlation_id']?.toString().trim() ?? '';
    final resolvedCorrelationId = requestedCorrelationId.isEmpty
        ? _nextCorrelationId(type: type, namespace: namespace)
        : requestedCorrelationId;
    final eventMetadata = <String, dynamic>{
      'correlation_id': resolvedCorrelationId,
      ...metadata,
    };

    _eventsController.add(
      StorageObservationEvent(
        type: type,
        namespace: namespace,
        path: path,
        timestamp: DateTime.now().toUtc(),
        origin: origin,
        result: result,
        metadata: eventMetadata,
      ),
    );
  }

  String _nextCorrelationId({
    required final StorageObservationType type,
    required final StorageNamespace namespace,
  }) {
    _observationSequence++;
    return '${type.name}_${namespace.value}_'
        '${DateTime.now().toUtc().microsecondsSinceEpoch}_'
        '$_observationSequence';
  }

  /// Closes kernel observation streams.
  Future<void> dispose() => _eventsController.close();

  String _preparationMessageFor(final MigrationPreparationResult result) {
    if (result.ok) {
      if (result.warnings.isNotEmpty) {
        return 'Migration prepared with warnings.';
      }
      return 'Migration preflight passed.';
    }
    if (result.issues.isEmpty) {
      return 'Migration preflight failed.';
    }
    return result.issues.join('; ');
  }
}

final class _NamespaceSyncReport {
  const _NamespaceSyncReport({
    required this.queueState,
    required this.result,
    required this.replayedEntries,
    required this.deadLetteredEntries,
    required this.stagedConflicts,
    this.metadata = const <String, dynamic>{},
  });

  final SyncQueueState queueState;
  final StorageOperationResult result;
  final int replayedEntries;
  final int deadLetteredEntries;
  final int stagedConflicts;
  final Map<String, dynamic> metadata;
}

final class _ConflictStageResult {
  const _ConflictStageResult({
    required this.conflicts,
    required this.stagedCount,
    required this.decisionState,
  });

  final List<SyncConflictEntry> conflicts;
  final int stagedCount;
  final DecisionState decisionState;
}
