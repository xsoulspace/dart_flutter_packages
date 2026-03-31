import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';
import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

class _MigrationFakeStorageProvider extends StorageProvider {
  _MigrationFakeStorageProvider({
    this.delay = Duration.zero,
    this.beforeCreate,
    this.beforeUpdate,
    // ignore: unused_element_parameter
    this.beforeRead,
    // ignore: unused_element_parameter
    this.beforeDelete,
    // ignore: unused_element_parameter
    this.beforeList,
  });

  bool _initialized = false;
  final Map<String, String> files = <String, String>{};
  final Duration delay;
  final Future<void> Function(String path)? beforeCreate;
  final Future<void> Function(String path)? beforeRead;
  final Future<void> Function(String path)? beforeUpdate;
  final Future<void> Function(String path)? beforeDelete;
  final Future<void> Function(String path)? beforeList;

  Future<void> _delay() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const ConfigurationException('Provider is not initialized.');
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
    if (beforeCreate != null) {
      await beforeCreate!(path);
    }
    await _delay();
    files[path] = content;
    return FileOperationResult.created(
      path: path,
      revisionId: 'rev:${files.length}',
    );
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    if (beforeRead != null) {
      await beforeRead!(path);
    }
    await _delay();
    return files[path];
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (beforeUpdate != null) {
      await beforeUpdate!(path);
    }
    await _delay();
    files[path] = content;
    return FileOperationResult.updated(
      path: path,
      revisionId: 'rev:${files.length}',
    );
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (beforeDelete != null) {
      await beforeDelete!(path);
    }
    await _delay();
    files.remove(path);
    return FileOperationResult.deleted(
      path: path,
      revisionId: 'rev:${files.length}',
    );
  }

  @override
  Future<List<FileEntry>> listDirectory(final String path) async {
    _ensureInitialized();
    if (beforeList != null) {
      await beforeList!(path);
    }
    await _delay();
    final normalizedPath = path == '.'
        ? ''
        : path.replaceAll(RegExp(r'^/+|/+$'), '');
    final entries = <FileEntry>[];
    for (final entry in files.keys) {
      if (normalizedPath.isEmpty) {
        entries.add(
          FileEntry(
            name: entry,
            isDirectory: false,
            size: files[entry]!.length,
            modifiedAt: DateTime.now(),
          ),
        );
        continue;
      }
      if (!entry.startsWith('$normalizedPath/')) {
        continue;
      }
      final remainder = entry.substring(normalizedPath.length + 1);
      if (remainder.contains('/')) {
        continue;
      }
      entries.add(
        FileEntry(
          name: remainder,
          isDirectory: false,
          size: files[entry]!.length,
          modifiedAt: DateTime.now(),
        ),
      );
    }
    return entries;
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {
    _ensureInitialized();
  }

  @override
  bool get supportsSync => false;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {}

  @override
  Future<void> dispose() async {}
}

Future<FileSystemConfig> _createConfig() async {
  final directory = await Directory.systemTemp.createTemp(
    'migration_manager_test_',
  );
  return FileSystemConfig(
    filePathConfig: FilePathConfig.create(
      path: directory.path,
      macOSBookmarkData: MacOSBookmark.fromDirectory(directory),
    ),
  );
}

StorageKernel _buildKernel({
  required final StorageProfile profile,
  required final _MigrationFakeStorageProvider settingsProvider,
  required final _MigrationFakeStorageProvider projectsProvider,
}) {
  final settingsService = StorageService(settingsProvider);
  final projectsService = StorageService(projectsProvider);

  return StorageKernel(
    profile: profile,
    resolver: InMemoryStorageProfileResolver(
      namespaceServices: <StorageNamespace, StorageService>{
        StorageNamespace.settings: settingsService,
        StorageNamespace.projects: projectsService,
      },
    ),
  );
}

Future<void> _writeManifest({
  required final StorageService service,
  required final String planId,
  required final MigrationStatus status,
  required final DateTime updatedAt,
  final DateTime? lockAcquiredAt,
  final String lockOwner = 'test_lock',
}) async {
  final lockData = lockAcquiredAt == null
      ? null
      : <String, dynamic>{
          'owner': lockOwner,
          'acquired_at': lockAcquiredAt.toUtc().toIso8601String(),
        };
  await service.saveFile(
    '.us/migrations/$planId.json',
    jsonEncode(<String, dynamic>{
      'schema_version': 1,
      'plan_id': planId,
      'status': status.name,
      'source_profile_hash': 'source_hash',
      'target_profile_hash': 'target_hash',
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'namespace_mappings': <String, String>{},
      'written': <String>[],
      'operations_total': 0,
      'written_count': 0,
      if (lockData != null) 'migration_lock': lockData,
    }),
  );
}

Map<String, dynamic> _decodeJsonMap(final Object? value) =>
    jsonDecodeMap(value).whenEmptyUse(const <String, dynamic>{});

List<Map<String, dynamic>> _decodeJsonMapList(final Object? value) {
  final decoded = jsonDecodeListAs<Object?>(value)
      .map(_decodeJsonMap)
      .where((final item) => item.isNotEmpty)
      .toList(growable: false);
  return decoded.whenEmptyUse(const <Map<String, dynamic>>[]);
}

List<String> _decodeJsonStringList(final Object? value) {
  final decoded = jsonDecodeListAs<Object?>(value)
      .map(jsonDecodeString)
      .where((final item) => item.isNotEmpty)
      .toList(growable: false);
  return decoded.whenEmptyUse(const <String>[]);
}

Map<String, dynamic> _decodeJsonMapField(
  final Map<String, dynamic> source,
  final String key,
) => _decodeJsonMap(source[key]);

List<Map<String, dynamic>> _decodeJsonMapListField(
  final Map<String, dynamic> source,
  final String key,
) => _decodeJsonMapList(source[key]);

String _decodeJsonStringField(
  final Map<String, dynamic> source,
  final String key,
) => jsonDecodeString(source[key]);

void main() {
  group('StorageProfileMigrationManager', () {
    test('copies files and records rollback path', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      for (final provider in <_MigrationFakeStorageProvider>[
        sourceSettings,
        sourceProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(sourceConfig);
      }
      for (final provider in <_MigrationFakeStorageProvider>[
        targetSettings,
        targetProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(targetConfig);
      }

      await sourceKernel.write(
        namespace: StorageNamespace.settings,
        path: 'profile.json',
        content: '{"mode":"source"}',
      );
      await sourceKernel.write(
        namespace: StorageNamespace.projects,
        path: 'note.txt',
        content: 'game save',
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'local_to_local',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final preparation = await endpoint.prepareMigration(plan: plan);
      expect(preparation.ok, isTrue);

      final execution = await endpoint.executeMigration(plan: plan);
      expect(execution.ok, isTrue);
      expect(execution.status, MigrationStatus.completed);

      final targetSettingsService = StorageService(targetSettings);
      final targetProjectsService = StorageService(targetProjects);
      expect(await targetSettingsService.readFile('profile.json'), isNotNull);
      expect(await targetProjectsService.readFile('note.txt'), isNotNull);

      final rollback = await endpoint.rollbackMigration(plan: plan);
      expect(rollback.ok, isTrue);
      expect(await targetSettingsService.readFile('profile.json'), isNull);
      expect(await targetProjectsService.readFile('note.txt'), isNull);
    });

    test(
      'execution report includes parity summary and checkpoint ledger',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        await StorageService(sourceSettings).initializeWithConfig(sourceConfig);
        await StorageService(targetSettings).initializeWithConfig(targetConfig);

        await sourceKernel.write(
          namespace: StorageNamespace.settings,
          path: 'profile.json',
          content: '{"mode":"source"}',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'parity_checkpoint_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final result = await endpoint.executeMigration(plan: plan);
        expect(result.ok, isTrue);
        expect(result.status, MigrationStatus.completed);

        final parity = _decodeJsonMap(result.metadata['parity_summary']);
        final countParity = _decodeJsonMapField(parity, 'count_parity');
        final checksumParity = _decodeJsonMapField(parity, 'checksum_parity');
        expect(countParity['source_operations'], 1);
        expect(countParity['processed_operations'], 1);
        expect(checksumParity['matched'], 1);

        final checkpoints = _decodeJsonMapList(
          result.metadata['checkpoint_ledger'],
        );
        expect(checkpoints.length, 1);
        expect(_decodeJsonStringField(checkpoints.single, 'status'), 'applied');
        expect(checkpoints.single['stable'], isTrue);

        final targetSettingsService = StorageService(targetSettings);
        final rawManifest = await targetSettingsService.readFile(
          '.us/migrations/parity_checkpoint_plan.json',
        );
        expect(rawManifest, isNotNull);
        final manifest = _decodeJsonMap(rawManifest);
        expect(manifest['checkpoints'], isA<List<dynamic>>());
        expect(manifest['parity_summary'], isA<Map<String, dynamic>>());
      },
    );

    test('applies transform hooks during execution', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      await StorageService(sourceProjects).initializeWithConfig(sourceConfig);
      await StorageService(targetProjects).initializeWithConfig(targetConfig);

      await sourceKernel.write(
        namespace: StorageNamespace.projects,
        path: 'legacy/old-id.json',
        content:
            '{"schema_version":"1","id":"old-id","title":"Draft","discarded":"x"}',
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'transform_plan',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
        metadata: const <String, dynamic>{
          'path_remap': <String, String>{'legacy': 'documents'},
          'id_remap_table': <String, String>{
            'old-id': 'new-id',
            'old-id.json': 'new-id.json',
          },
          'schema_transform': <String, String>{
            'field': 'schema_version',
            'from': '1',
            'to': '2',
          },
          'field_projection': <String, dynamic>{
            'include': <String>['schema_version', 'id', 'title'],
          },
        },
      );

      final result = await endpoint.executeMigration(plan: plan);
      expect(result.ok, isTrue);
      final transformed = await targetKernel.read(
        namespace: StorageNamespace.projects,
        path: 'documents/new-id.json',
      );
      expect(transformed, isNotNull);
      final decoded = _decodeJsonMap(transformed);
      expect(_decodeJsonStringField(decoded, 'schema_version'), '2');
      expect(_decodeJsonStringField(decoded, 'id'), 'new-id');
      expect(_decodeJsonStringField(decoded, 'title'), 'Draft');
      expect(decoded.containsKey('discarded'), isFalse);

      final checkpoints = _decodeJsonMapList(
        result.metadata['checkpoint_ledger'],
      );
      expect(checkpoints.single['transform_steps'], isA<List<dynamic>>());
      expect(
        _decodeJsonStringList(
          checkpoints.single['transform_steps'],
        ).contains('schema_transform'),
        isTrue,
      );
    });

    test('can rollback to the last stable checkpoint id', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      await StorageService(sourceSettings).initializeWithConfig(sourceConfig);
      await StorageService(targetSettings).initializeWithConfig(targetConfig);

      await sourceKernel.write(
        namespace: StorageNamespace.settings,
        path: 'a.json',
        content: '{"a":1}',
      );
      await sourceKernel.write(
        namespace: StorageNamespace.settings,
        path: 'b.json',
        content: '{"b":2}',
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final executePlan = MigrationPlan(
        id: 'checkpoint_rollback_plan',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final executed = await endpoint.executeMigration(plan: executePlan);
      expect(executed.ok, isTrue);
      final checkpoints = _decodeJsonMapList(
        executed.metadata['checkpoint_ledger'],
      );
      final checkpointId = _decodeJsonStringField(checkpoints.first, 'id');

      final rollback = await endpoint.rollbackMigration(
        plan: MigrationPlan(
          id: 'checkpoint_rollback_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
          metadata: <String, dynamic>{
            'rollback_to_checkpoint_id': checkpointId,
          },
        ),
      );

      expect(rollback.ok, isTrue);
      expect(
        await targetKernel.read(
          namespace: StorageNamespace.settings,
          path: 'a.json',
        ),
        isNotNull,
      );
      expect(
        await targetKernel.read(
          namespace: StorageNamespace.settings,
          path: 'b.json',
        ),
        isNull,
      );
    });

    test(
      'dry run can produce per-operation preview for conflict-aware migration mode',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        for (final provider in <_MigrationFakeStorageProvider>[
          sourceSettings,
          sourceProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(sourceConfig);
        }
        for (final provider in <_MigrationFakeStorageProvider>[
          targetSettings,
          targetProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(targetConfig);
        }

        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/new.txt',
          content: 'fresh',
        );
        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'different',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'original',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/same.txt',
          content: 'same',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'preview_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final result = await endpoint.executeMigrationWithOptions(
          plan: plan,
          dryRun: true,
          overwrite: false,
          collectDiffs: true,
        );

        expect(result.ok, isTrue);
        expect(result.status, MigrationStatus.prepared);
        final metadata = result.metadata;
        final preview = _decodeJsonMapListField(metadata, 'preflight_preview');
        expect(preview.length, 2);

        final byPath = <String, Map<String, dynamic>>{
          for (final item in preview)
            _decodeJsonStringField(item, 'source_path'): item,
        };
        final newItem = byPath['notes/new.txt'];
        final oldItem = byPath['notes/old.txt'];
        expect(newItem, isNotNull);
        expect(oldItem, isNotNull);
        expect(_decodeJsonStringField(newItem!, 'status'), 'create');
        expect(_decodeJsonStringField(oldItem!, 'status'), 'conflict');
        expect(
          _decodeJsonStringField(oldItem, 'decision_state'),
          DecisionState.needsUserDecision.name,
        );
        final newItemMetadata = _decodeJsonMapField(newItem, 'metadata');
        expect(
          _decodeJsonStringField(newItemMetadata, 'diff_summary'),
          'Target file missing.',
        );
      },
    );

    test(
      'execution can pause for decision when conflict appears in complex mode',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        for (final provider in <_MigrationFakeStorageProvider>[
          sourceSettings,
          sourceProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(sourceConfig);
        }
        for (final provider in <_MigrationFakeStorageProvider>[
          targetSettings,
          targetProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(targetConfig);
        }

        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'from_source',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'from_target',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'decision_pause_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final result = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          collectDiffs: true,
          pauseForDecisions: true,
        );

        expect(result.ok, isFalse);
        expect(result.status, MigrationStatus.prepared);
        final metadata = result.metadata;
        expect(metadata['pause_for_decisions'], isTrue);
        final pending = _decodeJsonMapListField(metadata, 'pending_decisions');
        expect(pending.length, 1);
        expect(
          _decodeJsonStringField(pending.first, 'source_path'),
          'notes/old.txt',
        );
        expect(
          _decodeJsonStringField(pending.first, 'operation_id'),
          isNotEmpty,
        );
        final preview = _decodeJsonMapListField(metadata, 'preflight_preview');
        final previewItem = preview.singleWhere(
          (final item) =>
              _decodeJsonStringField(item, 'source_path') == 'notes/old.txt',
          orElse: () => fail('Expected preview item not found.'),
        );
        expect(_decodeJsonStringField(previewItem, 'status'), 'conflict');
        expect(
          _decodeJsonStringField(previewItem, 'decision_state'),
          DecisionState.needsUserDecision.name,
        );
      },
    );

    test(
      'execution can resume after explicit conflict decisions are provided',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        for (final provider in <_MigrationFakeStorageProvider>[
          sourceSettings,
          sourceProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(sourceConfig);
        }
        for (final provider in <_MigrationFakeStorageProvider>[
          targetSettings,
          targetProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(targetConfig);
        }

        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/first.txt',
          content: 'first',
        );
        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'from_source',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/old.txt',
          content: 'from_target',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'decision_resume_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final paused = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          collectDiffs: true,
          pauseForDecisions: true,
        );
        expect(paused.ok, isFalse);
        expect(paused.status, MigrationStatus.prepared);
        final pending = _decodeJsonMapList(
          paused.metadata['pending_decisions'],
        );
        final operationId = _decodeJsonStringField(
          pending.single,
          'operation_id',
        );

        final resumed = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          collectDiffs: true,
          pauseForDecisions: true,
          decisionStates: <String, DecisionState>{
            operationId: DecisionState.autoResolved,
          },
        );
        expect(resumed.ok, isTrue);
        expect(resumed.status, MigrationStatus.completed);
        expect(
          await targetKernel.read(
            namespace: StorageNamespace.projects,
            path: 'notes/old.txt',
          ),
          'from_source',
        );
        expect(
          await targetKernel.read(
            namespace: StorageNamespace.projects,
            path: 'notes/first.txt',
          ),
          'first',
        );
      },
    );

    test(
      'can skip conflicting files with explicit conflict decisions',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        for (final provider in <_MigrationFakeStorageProvider>[
          sourceSettings,
          sourceProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(sourceConfig);
        }
        for (final provider in <_MigrationFakeStorageProvider>[
          targetSettings,
          targetProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(targetConfig);
        }

        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/conflict.txt',
          content: 'source',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/conflict.txt',
          content: 'target',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'skip_decision_plan',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final first = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          pauseForDecisions: true,
          collectDiffs: true,
        );
        expect(first.ok, isFalse);
        expect(first.status, MigrationStatus.prepared);
        final pending = _decodeJsonMapList(first.metadata['pending_decisions']);
        expect(
          _decodeJsonStringField(pending.single, 'source_path'),
          'notes/conflict.txt',
        );

        final operationId = _decodeJsonStringField(
          pending.single,
          'operation_id',
        );
        final result = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          pauseForDecisions: true,
          collectDiffs: true,
          decisionStates: <String, DecisionState>{
            operationId: DecisionState.blocked,
          },
        );

        expect(result.ok, isTrue);
        expect(result.status, MigrationStatus.completed);
        expect(
          await targetKernel.read(
            namespace: StorageNamespace.projects,
            path: 'notes/conflict.txt',
          ),
          'target',
        );
      },
    );

    test(
      'can mix overwrite and skip conflicting files with explicit decisions',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        for (final provider in <_MigrationFakeStorageProvider>[
          sourceSettings,
          sourceProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(sourceConfig);
        }
        for (final provider in <_MigrationFakeStorageProvider>[
          targetSettings,
          targetProjects,
        ]) {
          await StorageService(provider).initializeWithConfig(targetConfig);
        }

        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/overwrite.txt',
          content: 'source-keep',
        );
        await sourceKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/skip.txt',
          content: 'source-skip',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/overwrite.txt',
          content: 'target-old',
        );
        await targetKernel.write(
          namespace: StorageNamespace.projects,
          path: 'notes/skip.txt',
          content: 'target-skip',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'mixed_conflict_decisions',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final paused = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          pauseForDecisions: true,
          collectDiffs: true,
        );
        expect(paused.ok, isFalse);
        expect(paused.status, MigrationStatus.prepared);
        final pending = _decodeJsonMapList(
          paused.metadata['pending_decisions'],
        );
        expect(pending.length, 2);

        final overwriteEntry = pending.firstWhere(
          (final item) =>
              _decodeJsonStringField(item, 'source_path') ==
              'notes/overwrite.txt',
        );
        final overwriteDecision = <String, MigrationDecisionAction>{
          _decodeJsonStringField(overwriteEntry, 'operation_id'):
              MigrationDecisionAction.overwrite,
        };
        final skipEntry = pending.firstWhere(
          (final item) =>
              _decodeJsonStringField(item, 'source_path') == 'notes/skip.txt',
        );
        final skipDecision = <String, MigrationDecisionAction>{
          _decodeJsonStringField(skipEntry, 'operation_id'):
              MigrationDecisionAction.skip,
        };
        final decisions = <String, MigrationDecisionAction>{};
        decisions.addAll(overwriteDecision);
        decisions.addAll(skipDecision);

        final resumed = await endpoint.executeMigrationWithOptions(
          plan: plan,
          overwrite: false,
          pauseForDecisions: true,
          collectDiffs: true,
          decisionActions: decisions,
        );
        expect(resumed.ok, isTrue);
        expect(resumed.status, MigrationStatus.completed);
        expect(
          await targetKernel.read(
            namespace: StorageNamespace.projects,
            path: 'notes/overwrite.txt',
          ),
          'source-keep',
        );
        expect(
          await targetKernel.read(
            namespace: StorageNamespace.projects,
            path: 'notes/skip.txt',
          ),
          'target-skip',
        );
      },
    );

    test('can abort migration with explicit abort decision', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      for (final provider in <_MigrationFakeStorageProvider>[
        sourceSettings,
        sourceProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(sourceConfig);
      }
      for (final provider in <_MigrationFakeStorageProvider>[
        targetSettings,
        targetProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(targetConfig);
      }

      await sourceKernel.write(
        namespace: StorageNamespace.projects,
        path: 'notes/a_conflict.txt',
        content: 'source',
      );
      await targetKernel.write(
        namespace: StorageNamespace.projects,
        path: 'notes/a_conflict.txt',
        content: 'target',
      );
      await sourceKernel.write(
        namespace: StorageNamespace.projects,
        path: 'notes/z_another.txt',
        content: 'source-two',
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'abort_decision_plan',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final paused = await endpoint.executeMigrationWithOptions(
        plan: plan,
        overwrite: false,
        pauseForDecisions: true,
        collectDiffs: true,
      );
      expect(paused.ok, isFalse);
      expect(paused.status, MigrationStatus.prepared);
      final pending = _decodeJsonMapList(paused.metadata['pending_decisions']);
      final conflictOperationId = _decodeJsonStringField(
        pending.single,
        'operation_id',
      );

      final aborted = await endpoint.executeMigrationWithOptions(
        plan: plan,
        overwrite: false,
        pauseForDecisions: true,
        collectDiffs: true,
        decisionActions: <String, MigrationDecisionAction>{
          conflictOperationId: MigrationDecisionAction.abort,
        },
      );

      expect(aborted.ok, isFalse);
      expect(aborted.status, MigrationStatus.failed);
      expect(aborted.message, contains('aborted by user'));
      expect(
        await targetKernel.read(
          namespace: StorageNamespace.projects,
          path: 'notes/a_conflict.txt',
        ),
        'target',
      );
      expect(
        await targetKernel.read(
          namespace: StorageNamespace.projects,
          path: 'notes/z_another.txt',
        ),
        'source-two',
      );
    });

    test('blocks concurrent execute operations for same plan id', () async {
      final writeStarted = Completer<void>();
      final writeGate = Completer<void>();
      final sourceSettings = _MigrationFakeStorageProvider(
        delay: const Duration(milliseconds: 50),
      );
      final sourceProjects = _MigrationFakeStorageProvider(
        delay: const Duration(milliseconds: 50),
      );
      final targetSettings = _MigrationFakeStorageProvider(
        delay: const Duration(milliseconds: 50),
        beforeCreate: (final path) async {
          if (!path.startsWith('.us/migrations/')) {
            if (!writeStarted.isCompleted) {
              writeStarted.complete();
            }
            await writeGate.future;
          }
        },
        beforeUpdate: (final path) async {
          if (!path.startsWith('.us/migrations/')) {
            if (!writeStarted.isCompleted) {
              writeStarted.complete();
            }
            await writeGate.future;
          }
        },
      );
      final targetProjects = _MigrationFakeStorageProvider(
        delay: const Duration(milliseconds: 50),
      );

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      for (final provider in <_MigrationFakeStorageProvider>[
        sourceSettings,
        sourceProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(sourceConfig);
      }
      for (final provider in <_MigrationFakeStorageProvider>[
        targetSettings,
        targetProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(targetConfig);
      }

      for (var index = 0; index < 3; index++) {
        await sourceKernel.write(
          namespace: StorageNamespace.settings,
          path: 'settings_$index.json',
          content: '{"index":$index}',
        );
      }

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'concurrent_plan',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final first = endpoint.executeMigration(plan: plan);
      await writeStarted.future;
      final second = endpoint.executeMigration(plan: plan);
      writeGate.complete();

      final results = await Future.wait(<Future<MigrationExecutionResult>>[
        first,
        second,
      ]);
      expect(results.first.ok, isTrue);
      expect(results.first.status, MigrationStatus.completed);
      expect(results[1].ok, isFalse);
      expect(results[1].status, MigrationStatus.failed);
      expect(results[1].message, contains('already in progress'));
    });

    test('allows execution after stale execution lock', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      for (final provider in <_MigrationFakeStorageProvider>[
        sourceSettings,
        sourceProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(sourceConfig);
      }
      final targetService = StorageService(targetSettings);
      await targetService.initializeWithConfig(targetConfig);

      await _writeManifest(
        service: targetService,
        planId: 'stale_lock',
        status: MigrationStatus.executing,
        updatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'stale_lock',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final result = await endpoint.executeMigration(plan: plan);
      expect(result.ok, isTrue);
      expect(result.status, MigrationStatus.completed);
    });

    test('rejects execution while a fresh lock exists in manifest', () async {
      final sourceSettings = _MigrationFakeStorageProvider();
      final sourceProjects = _MigrationFakeStorageProvider();
      final targetSettings = _MigrationFakeStorageProvider();
      final targetProjects = _MigrationFakeStorageProvider();

      final sourceKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'source',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: sourceSettings,
        projectsProvider: sourceProjects,
      );
      final targetKernel = _buildKernel(
        profile: const StorageProfile(
          name: 'target',
          namespaces: <StorageNamespaceProfile>[
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.localOnly,
            ),
          ],
        ),
        settingsProvider: targetSettings,
        projectsProvider: targetProjects,
      );

      final sourceConfig = await _createConfig();
      final targetConfig = await _createConfig();
      for (final provider in <_MigrationFakeStorageProvider>[
        sourceSettings,
        sourceProjects,
      ]) {
        await StorageService(provider).initializeWithConfig(sourceConfig);
      }
      final targetService = StorageService(targetSettings);
      await targetService.initializeWithConfig(targetConfig);

      await _writeManifest(
        service: targetService,
        planId: 'active_lock',
        status: MigrationStatus.executing,
        updatedAt: DateTime.now().toUtc(),
      );

      final endpoint = StorageProfileMigrationEndpoint(
        sourceKernel: sourceKernel,
        targetKernel: targetKernel,
      );
      final plan = MigrationPlan(
        id: 'active_lock',
        sourceProfileHash: 'source_hash',
        targetProfileHash: 'target_hash',
        createdAt: DateTime.now(),
      );

      final result = await endpoint.executeMigration(plan: plan);
      expect(result.ok, isFalse);
      expect(result.status, MigrationStatus.failed);
      expect(result.message, contains('already in progress'));
    });

    test(
      'uses manifest lock metadata timestamp to gate concurrent execution',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        await StorageService(sourceSettings).initializeWithConfig(sourceConfig);
        await StorageService(targetSettings).initializeWithConfig(targetConfig);

        final targetService = StorageService(targetSettings);
        await _writeManifest(
          service: targetService,
          planId: 'fresh_lock_via_metadata',
          status: MigrationStatus.executing,
          updatedAt: DateTime.now(),
          lockAcquiredAt: DateTime.now(),
          lockOwner: 'another_process',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'fresh_lock_via_metadata',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final result = await endpoint.executeMigration(plan: plan);
        expect(result.ok, isFalse);
        expect(result.status, MigrationStatus.failed);
        expect(result.message, contains('already in progress'));
      },
    );

    test(
      'allows execution when manifest lock metadata has expired TTL',
      () async {
        final sourceSettings = _MigrationFakeStorageProvider();
        final sourceProjects = _MigrationFakeStorageProvider();
        final targetSettings = _MigrationFakeStorageProvider();
        final targetProjects = _MigrationFakeStorageProvider();

        final sourceKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'source',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: sourceSettings,
          projectsProvider: sourceProjects,
        );
        final targetKernel = _buildKernel(
          profile: const StorageProfile(
            name: 'target',
            namespaces: <StorageNamespaceProfile>[
              StorageNamespaceProfile(
                namespace: StorageNamespace.settings,
                policy: StoragePolicy.localOnly,
              ),
            ],
          ),
          settingsProvider: targetSettings,
          projectsProvider: targetProjects,
        );

        final sourceConfig = await _createConfig();
        final targetConfig = await _createConfig();
        await StorageService(sourceSettings).initializeWithConfig(sourceConfig);
        await StorageService(targetSettings).initializeWithConfig(targetConfig);

        final targetService = StorageService(targetSettings);
        await _writeManifest(
          service: targetService,
          planId: 'stale_lock_via_metadata',
          status: MigrationStatus.executing,
          updatedAt: DateTime.now(),
          lockAcquiredAt: DateTime.now().subtract(const Duration(minutes: 25)),
          lockOwner: 'another_process',
        );

        final endpoint = StorageProfileMigrationEndpoint(
          sourceKernel: sourceKernel,
          targetKernel: targetKernel,
        );
        final plan = MigrationPlan(
          id: 'stale_lock_via_metadata',
          sourceProfileHash: 'source_hash',
          targetProfileHash: 'target_hash',
          createdAt: DateTime.now(),
        );

        final result = await endpoint.executeMigration(plan: plan);
        expect(result.ok, isTrue);
        expect(result.status, MigrationStatus.completed);
      },
    );
  });

  test('storage kernel rollback without endpoint fails clearly', () async {
    final settingsProvider = _MigrationFakeStorageProvider();
    const profile = StorageProfile(
      name: 'no-endpoint',
      namespaces: <StorageNamespaceProfile>[
        StorageNamespaceProfile(
          namespace: StorageNamespace.settings,
          policy: StoragePolicy.localOnly,
        ),
      ],
    );
    final kernel = _buildKernel(
      profile: profile,
      settingsProvider: settingsProvider,
      projectsProvider: _MigrationFakeStorageProvider(),
    );
    await StorageService(
      settingsProvider,
    ).initializeWithConfig(await _createConfig());

    final result = await kernel.rollbackMigration(
      plan: MigrationPlan(
        id: 'missing_endpoint',
        sourceProfileHash: 'a',
        targetProfileHash: 'b',
        createdAt: DateTime.now(),
      ),
    );
    expect(result.ok, isFalse);
    expect(result.status, MigrationStatus.failed);
  });

  test(
    'storage kernel execute migration without endpoint fails clearly',
    () async {
      final settingsProvider = _MigrationFakeStorageProvider();
      const profile = StorageProfile(
        name: 'no-endpoint-exec',
        namespaces: <StorageNamespaceProfile>[
          StorageNamespaceProfile(
            namespace: StorageNamespace.settings,
            policy: StoragePolicy.localOnly,
          ),
        ],
      );

      final kernel = _buildKernel(
        profile: profile,
        settingsProvider: settingsProvider,
        projectsProvider: _MigrationFakeStorageProvider(),
      );
      await StorageService(
        settingsProvider,
      ).initializeWithConfig(await _createConfig());

      final result = await kernel.executeMigration(
        plan: MigrationPlan(
          id: 'missing_endpoint_exec',
          sourceProfileHash: 'a',
          targetProfileHash: 'b',
          createdAt: DateTime.now(),
        ),
      );
      expect(result.ok, isFalse);
      expect(result.status, MigrationStatus.failed);
    },
  );
}
