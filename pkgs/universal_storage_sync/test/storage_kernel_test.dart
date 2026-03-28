import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync/src/decision_store.dart';
import 'package:universal_storage_sync/src/storage_kernel.dart';
import 'package:universal_storage_sync/src/storage_profile_resolver.dart';

class _KernelFakeStorageProvider extends StorageProvider {
  _KernelFakeStorageProvider({
    this.syncEnabled = false,
    final List<Object> syncErrors = const <Object>[],
  }) : _syncErrors = List<Object>.from(syncErrors);

  final bool syncEnabled;
  final List<Object> _syncErrors;
  final Map<String, String> files = <String, String>{};
  int syncCalls = 0;
  String? lastPullMergeStrategy;
  String? lastPushConflictStrategy;
  var _initialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const AuthenticationException('Provider is not initialized.');
    }
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files[path] = content;
    return FileOperationResult.created(
      path: path,
      metadata: const <String, dynamic>{
        'durability_protocol': 'fake_journal_v1',
        'durability_sequence': 1,
      },
    );
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    return files[path];
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files[path] = content;
    return FileOperationResult.updated(
      path: path,
      metadata: const <String, dynamic>{
        'durability_protocol': 'fake_journal_v1',
        'durability_sequence': 2,
      },
    );
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    files.remove(path);
    return FileOperationResult.deleted(
      path: path,
      metadata: const <String, dynamic>{
        'durability_protocol': 'fake_journal_v1',
        'durability_sequence': 3,
      },
    );
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    return files.keys
        .map(
          (final e) => FileEntry(
            name: e,
            isDirectory: false,
            size: files[e]!.length,
            modifiedAt: DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {
    _ensureInitialized();
  }

  @override
  bool get supportsSync => syncEnabled;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    _ensureInitialized();
    lastPullMergeStrategy = pullMergeStrategy;
    lastPushConflictStrategy = pushConflictStrategy;
    if (!syncEnabled) return;
    syncCalls++;
    if (_syncErrors.isEmpty) {
      return;
    }

    final error = _syncErrors.removeAt(0);
    if (error is Exception) {
      throw error;
    }
    if (error is Error) {
      throw error;
    }
    throw Exception(error.toString());
  }

  @override
  Future<void> dispose() async {}
}

final class _KernelMigrationEndpointFake implements MigrationEndpoint {
  _KernelMigrationEndpointFake({required this.executionResult});

  int executeWithOptionsCalls = 0;
  MigrationPlan? lastPlan;
  bool? lastOverwrite;
  bool? lastDryRun;
  bool? lastCollectDiffs;
  bool? lastPauseForDecisions;
  Map<String, MigrationDecisionAction> lastDecisionActions = const {};
  Map<String, DecisionState> lastDecisionStates = const {};

  final MigrationExecutionResult executionResult;

  @override
  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  }) async => MigrationPreparationResult(
    ok: true,
    metadata: <String, dynamic>{'plan_id': plan.id},
  );

  @override
  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  }) async => executeMigrationWithOptions(plan: plan);

  @override
  Future<MigrationExecutionResult> executeMigrationWithOptions({
    required final MigrationPlan plan,
    final bool overwrite = true,
    final bool dryRun = false,
    final bool collectDiffs = false,
    final bool pauseForDecisions = false,
    final Map<String, MigrationDecisionAction> decisionActions =
        const <String, MigrationDecisionAction>{},
    final Map<String, DecisionState> decisionStates =
        const <String, DecisionState>{},
  }) async {
    executeWithOptionsCalls++;
    lastPlan = plan;
    lastOverwrite = overwrite;
    lastDryRun = dryRun;
    lastCollectDiffs = collectDiffs;
    lastPauseForDecisions = pauseForDecisions;
    lastDecisionActions = Map<String, MigrationDecisionAction>.from(
      decisionActions,
    );
    lastDecisionStates = Map<String, DecisionState>.from(decisionStates);
    return executionResult;
  }

  @override
  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  }) async => const MigrationExecutionResult(
    ok: true,
    status: MigrationStatus.rolledBack,
  );
}

Future<FileSystemConfig> _createConfig() async {
  final tempDirectory = await Directory.systemTemp.createTemp('kernel_test_');
  return FileSystemConfig(
    filePathConfig: FilePathConfig.create(
      path: tempDirectory.path,
      macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
    ),
  );
}

void main() {
  group('StorageKernel', () {
    test('routes write/read by namespace', () async {
      final settingsProvider = _KernelFakeStorageProvider();
      final projectsProvider = _KernelFakeStorageProvider();

      final settingsService = StorageService(settingsProvider);
      final projectsService = StorageService(projectsProvider);
      await settingsService.initializeWithConfig(await _createConfig());
      await projectsService.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'test_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
          ),
        ],
      );

      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.settings: settingsService,
          StorageNamespace.projects: projectsService,
        },
      );

      final kernel = StorageKernel(profile: profile, resolver: resolver);
      await kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"theme":"dark"}',
      );

      expect(settingsProvider.files['settings.json'], isNotNull);
      expect(projectsProvider.files['settings.json'], isNull);

      final content = await kernel.read(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
      );
      expect(content, contains('"theme"'));
    });

    test(
      'degrades complex interaction to minimal when capabilities are missing',
      () async {
        final provider = _KernelFakeStorageProvider();
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'complex_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              syncInteractionLevel: SyncInteractionLevel.complex,
              requiredCapabilities: StorageCapabilities(
                supportsDiff: true,
                supportsHistory: true,
              ),
            ),
          ],
        );

        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
          namespaceCapabilities: <StorageNamespace, StorageCapabilities>{
            StorageNamespace.projects: StorageCapabilities.none,
          },
        );

        final kernel = StorageKernel(profile: profile, resolver: resolver);
        final level = await kernel.resolveInteractionLevel(
          StorageNamespace.projects,
        );
        expect(level, SyncInteractionLevel.minimal);
        expect(
          kernel.interactionDowngradeReasonFor(StorageNamespace.projects),
          isNotNull,
        );
      },
    );

    test(
      'sync skips local_only namespace and syncs remote-capable namespace',
      () async {
        final settingsProvider = _KernelFakeStorageProvider(syncEnabled: true);
        final projectsProvider = _KernelFakeStorageProvider(syncEnabled: true);

        final settingsService = StorageService(settingsProvider);
        final projectsService = StorageService(projectsProvider);
        await settingsService.initializeWithConfig(await _createConfig());
        await projectsService.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'sync_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
            ),
          ],
        );

        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.settings: settingsService,
            StorageNamespace.projects: projectsService,
          },
        );

        final kernel = StorageKernel(profile: profile, resolver: resolver);
        await kernel.sync();

        expect(settingsProvider.syncCalls, 0);
        expect(projectsProvider.syncCalls, 1);
      },
    );

    test('sync marks remote-required namespace as failed when provider '
        'does not support sync', () async {
      final provider = _KernelFakeStorageProvider();
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'sync_unsupported_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            remoteEngineId: 'github',
          ),
        ],
      );
      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.projects: service,
        },
      );

      final kernel = StorageKernel(profile: profile, resolver: resolver);
      final syncEventFuture = kernel
          .observe(namespace: StorageNamespace.projects)
          .where((final event) => event.type == StorageObservationType.synced)
          .first;

      await kernel.write(
        namespace: StorageNamespace.projects,
        path: 'tasks/unsupported.json',
        content: '{"id":"unsupported"}',
      );
      await kernel.sync(namespace: StorageNamespace.projects);

      final syncEvent = await syncEventFuture;
      expect(provider.syncCalls, 0);
      expect(syncEvent.result, isNotNull);
      expect(syncEvent.result!.success, isFalse);
      expect(syncEvent.result!.decisionState, DecisionState.blocked);
      expect(
        syncEvent.result!.message,
        contains('does not support remote synchronization'),
      );
      expect(
        syncEvent.result!.metadata['error_type'],
        'CapabilityMismatchException',
      );
    });

    test('observe emits created and updated events for namespace', () async {
      final provider = _KernelFakeStorageProvider();
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'observe_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
        ],
      );

      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.settings: service,
        },
      );
      final kernel = StorageKernel(profile: profile, resolver: resolver);

      final eventsFuture = kernel
          .observe(namespace: StorageNamespace.settings)
          .take(2)
          .toList();

      await kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"theme":"dark"}',
      );
      await kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"theme":"light"}',
      );

      final events = await eventsFuture;
      expect(events.length, 2);
      expect(events.first.type, StorageObservationType.created);
      expect(events.last.type, StorageObservationType.updated);
      expect(events.first.path, 'settings.json');
      expect(events.last.path, 'settings.json');
    });

    test('observe propagates provider durability metadata', () async {
      final provider = _KernelFakeStorageProvider();
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'observe_durability_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
        ],
      );
      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.settings: service,
        },
      );
      final kernel = StorageKernel(profile: profile, resolver: resolver);

      final eventFuture = kernel
          .observe(namespace: StorageNamespace.settings)
          .where((final event) => event.type == StorageObservationType.created)
          .first;
      await kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"theme":"dark"}',
      );
      final event = await eventFuture;

      expect(event.metadata['durability_protocol'], 'fake_journal_v1');
      expect(event.metadata['durability_sequence'], 1);
    });

    test('observe emits correlation id metadata for events', () async {
      final provider = _KernelFakeStorageProvider();
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'observe_correlation_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
        ],
      );
      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.settings: service,
        },
      );
      final kernel = StorageKernel(profile: profile, resolver: resolver);

      final eventFuture = kernel
          .observe(namespace: StorageNamespace.settings)
          .where((final event) => event.type == StorageObservationType.created)
          .first;
      await kernel.write(
        namespace: StorageNamespace.settings,
        path: 'settings.json',
        content: '{"theme":"dark"}',
      );
      final event = await eventFuture;

      final correlationId = event.metadata['correlation_id']?.toString();
      expect(correlationId, isNotNull);
      expect(correlationId, isNotEmpty);
    });

    test('observe emits syncSkipped and synced events', () async {
      final settingsProvider = _KernelFakeStorageProvider(syncEnabled: true);
      final projectsProvider = _KernelFakeStorageProvider(syncEnabled: true);

      final settingsService = StorageService(settingsProvider);
      final projectsService = StorageService(projectsProvider);
      await settingsService.initializeWithConfig(await _createConfig());
      await projectsService.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'observe_sync_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
          ),
        ],
      );

      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.settings: settingsService,
          StorageNamespace.projects: projectsService,
        },
      );

      final kernel = StorageKernel(profile: profile, resolver: resolver);
      final syncEventsFuture = kernel
          .observe()
          .where(
            (final event) =>
                event.type == StorageObservationType.syncSkipped ||
                event.type == StorageObservationType.synced,
          )
          .take(2)
          .toList();

      await kernel.sync();
      final events = await syncEventsFuture;

      expect(events.length, 2);
      expect(
        events.any(
          (final e) =>
              e.type == StorageObservationType.syncSkipped &&
              e.namespace == StorageNamespace.settings,
        ),
        isTrue,
      );
      expect(
        events.any(
          (final e) =>
              e.type == StorageObservationType.synced &&
              e.namespace == StorageNamespace.projects,
        ),
        isTrue,
      );
    });

    test('decision store persists decisions across kernel instances', () async {
      final provider = _KernelFakeStorageProvider();
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'decision_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            remoteEngineId: 'github',
          ),
        ],
      );

      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.projects: service,
        },
      );
      final sharedStore = InMemoryDecisionStore();
      final kernel1 = StorageKernel(
        profile: profile,
        resolver: resolver,
        decisionStore: sharedStore,
      );

      const decision = StorageDecision(
        id: 'decision-1',
        namespace: StorageNamespace.projects,
        reason: 'Conflict requires user choice.',
      );
      await kernel1.resolveDecision(
        decision: decision,
        targetState: DecisionState.needsUserDecision,
        note: 'awaiting user input',
      );

      final kernel2 = StorageKernel(
        profile: profile,
        resolver: resolver,
        decisionStore: sharedStore,
      );
      final loadedState = await kernel2.decisionState(decision.id);
      final allStates = await kernel2.decisionStatesSnapshot();

      expect(loadedState, DecisionState.needsUserDecision);
      expect(allStates[decision.id], DecisionState.needsUserDecision);
    });

    test(
      'outbox is durable and deduplicates deterministic entry ids',
      () async {
        final provider = _KernelFakeStorageProvider(syncEnabled: true);
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'outbox_durability_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'github',
            ),
          ],
        );
        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
        );

        final kernel1 = StorageKernel(profile: profile, resolver: resolver);
        await kernel1.write(
          namespace: StorageNamespace.projects,
          path: 'tasks/1.json',
          content: '{"id":1}',
        );
        await kernel1.write(
          namespace: StorageNamespace.projects,
          path: 'tasks/1.json',
          content: '{"id":1}',
        );

        final queuedFromKernel1 = await kernel1.outboxSnapshot(
          StorageNamespace.projects,
        );
        expect(queuedFromKernel1, hasLength(1));

        final kernel2 = StorageKernel(profile: profile, resolver: resolver);
        final queuedFromKernel2 = await kernel2.outboxSnapshot(
          StorageNamespace.projects,
        );
        expect(queuedFromKernel2, hasLength(1));
        expect(queuedFromKernel2.single.id, queuedFromKernel1.single.id);
      },
    );

    test('sync replays outbox after transient failure', () async {
      final provider = _KernelFakeStorageProvider(
        syncEnabled: true,
        syncErrors: const <Object>[NetworkException('offline')],
      );
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'transient_sync_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            remoteEngineId: 'github',
            queuePolicy: SyncQueuePolicy(
              initialBackoffMs: 1,
              maxBackoffMs: 2,
              maxEntryAgeMs: 60000,
            ),
          ),
        ],
      );
      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.projects: service,
        },
      );
      final kernel = StorageKernel(profile: profile, resolver: resolver);

      await kernel.write(
        namespace: StorageNamespace.projects,
        path: 'tasks/2.json',
        content: '{"id":2}',
      );
      await kernel.sync();

      final queuedAfterFailure = await kernel.outboxSnapshot(
        StorageNamespace.projects,
      );
      expect(queuedAfterFailure, hasLength(1));
      expect(queuedAfterFailure.single.attempts, 1);

      // Wait for the minimal backoff window to expire before replay.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await kernel.sync();

      final queuedAfterRecovery = await kernel.outboxSnapshot(
        StorageNamespace.projects,
      );
      expect(queuedAfterRecovery, isEmpty);
      expect(provider.syncCalls, 2);
      expect(provider.lastPushConflictStrategy, 'rebase-local');
    });

    test(
      'sync sends failed operation to dead-letter after retry budget',
      () async {
        final provider = _KernelFakeStorageProvider(
          syncEnabled: true,
          syncErrors: const <Object>[NetworkException('still offline')],
        );
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'dead_letter_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'github',
              queuePolicy: SyncQueuePolicy(
                maxRetries: 1,
                initialBackoffMs: 1,
                maxBackoffMs: 1,
                maxEntryAgeMs: 60000,
              ),
            ),
          ],
        );
        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
        );
        final kernel = StorageKernel(profile: profile, resolver: resolver);

        await kernel.write(
          namespace: StorageNamespace.projects,
          path: 'tasks/3.json',
          content: '{"id":3}',
        );
        await kernel.sync();

        final outbox = await kernel.outboxSnapshot(StorageNamespace.projects);
        final deadLetter = await kernel.deadLetterSnapshot(
          StorageNamespace.projects,
        );
        expect(outbox, isEmpty);
        expect(deadLetter, hasLength(1));
        expect(deadLetter.single.lastError, contains('still offline'));
      },
    );

    test('conflicts are staged and can be blocked via decision', () async {
      final provider = _KernelFakeStorageProvider(
        syncEnabled: true,
        syncErrors: const <Object>[SyncConflictException('conflict detected')],
      );
      final service = StorageService(provider);
      await service.initializeWithConfig(await _createConfig());

      const profile = StorageProfile(
        name: 'conflict_profile',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.projects,
            policy: StoragePolicy.optimisticSync,
            remoteEngineId: 'github',
            queuePolicy: SyncQueuePolicy(
              initialBackoffMs: 1,
              maxBackoffMs: 1,
              maxEntryAgeMs: 60000,
            ),
          ),
        ],
      );
      final resolver = InMemoryStorageProfileResolver(
        namespaceServices: <StorageNamespace, StorageService>{
          StorageNamespace.projects: service,
        },
      );
      final kernel = StorageKernel(profile: profile, resolver: resolver);

      await kernel.write(
        namespace: StorageNamespace.projects,
        path: 'tasks/4.json',
        content: '{"id":4}',
      );
      await kernel.sync();

      final conflicts = await kernel.conflictSnapshot(
        StorageNamespace.projects,
      );
      expect(conflicts, hasLength(1));
      expect(conflicts.single.decisionState, DecisionState.needsUserDecision);
      expect(
        await kernel.decisionState('decision_${conflicts.single.id}'),
        DecisionState.needsUserDecision,
      );

      final decision = StorageDecision(
        id: 'decision_${conflicts.single.id}',
        namespace: StorageNamespace.projects,
        reason: conflicts.single.reason,
        metadata: <String, dynamic>{
          'conflict_entry_id': conflicts.single.id,
          'outbox_entry_id': conflicts.single.outboxEntryId,
        },
      );
      await kernel.resolveDecision(
        decision: decision,
        targetState: DecisionState.blocked,
        note: 'stop replaying this conflict',
      );

      final outbox = await kernel.outboxSnapshot(StorageNamespace.projects);
      final deadLetter = await kernel.deadLetterSnapshot(
        StorageNamespace.projects,
      );
      final remainingConflicts = await kernel.conflictSnapshot(
        StorageNamespace.projects,
      );
      expect(outbox, isEmpty);
      expect(
        deadLetter.any(
          (final entry) => entry.id == conflicts.single.outboxEntryId,
        ),
        isTrue,
      );
      expect(remainingConflicts, isEmpty);
    });

    test(
      'execution propagates metadata options to migration endpoint',
      () async {
        final provider = _KernelFakeStorageProvider();
        final service = StorageService(provider);
        await service.initializeWithConfig(await _createConfig());

        const profile = StorageProfile(
          name: 'metadata_profile',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
            ),
          ],
        );
        final resolver = InMemoryStorageProfileResolver(
          namespaceServices: <StorageNamespace, StorageService>{
            StorageNamespace.projects: service,
          },
        );

        final decisionStore = InMemoryDecisionStore();
        await decisionStore.saveState(
          decisionId: 'decision-1',
          state: DecisionState.autoResolved,
        );

        final fakeEndpoint = _KernelMigrationEndpointFake(
          executionResult: const MigrationExecutionResult(
            ok: true,
            status: MigrationStatus.completed,
            message: 'ok',
          ),
        );
        final kernel = StorageKernel(
          profile: profile,
          resolver: resolver,
          migrationEndpoint: fakeEndpoint,
          decisionStore: decisionStore,
        );

        final plan = MigrationPlan(
          id: 'metadata-plan',
          sourceProfileHash: 'source',
          targetProfileHash: 'target',
          createdAt: DateTime.now(),
          metadata: <String, dynamic>{
            'overwrite': false,
            'dry_run': true,
            'migration_interaction_level': SyncInteractionLevel.complex.name,
          },
        );

        final result = await kernel.executeMigration(plan: plan);
        expect(result.ok, isTrue);
        expect(fakeEndpoint.executeWithOptionsCalls, 1);
        expect(fakeEndpoint.lastPlan?.id, plan.id);
        expect(fakeEndpoint.lastOverwrite, isFalse);
        expect(fakeEndpoint.lastDryRun, isTrue);
        expect(fakeEndpoint.lastPauseForDecisions, isTrue);
        expect(fakeEndpoint.lastCollectDiffs, isTrue);
        expect(
          fakeEndpoint.lastDecisionStates,
          containsPair('decision-1', DecisionState.autoResolved),
        );
      },
    );
  });
}
