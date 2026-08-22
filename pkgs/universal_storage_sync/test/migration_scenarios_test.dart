import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_local_db/universal_storage_local_db.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// Real-backend migration scenarios:
/// - local_db → filesystem (one-shot import)
/// - filesystem → git_offline (adopt into versioned storage)
/// - git_offline → local_db (export back to plain KV)
/// - local_db → git_offline directly
///
/// Uses the production StorageProfileMigrationManager over real kernels so
/// the results reflect actual end-user migration behavior, including
/// checksum verification and manifest persistence.
void main() {
  Future<StorageKernel> buildLocalDbKernel({
    required final String keyspacePrefix,
  }) async {
    // One provider per namespace: LocalDbStorageProvider isolates by keyspace
    // prefix, so sharing one instance across namespaces would leak entries.
    final namespaceServices = <StorageNamespace, StorageService>{};
    for (final namespace in [
      StorageNamespace.settings,
      StorageNamespace.projects,
    ]) {
      final provider = LocalDbStorageProvider(
        localDb: _SharedInMemoryLocalDb(),
      );
      await provider.initWithConfig(
        LocalDbStorageConfig(
          keyspacePrefix: '${keyspacePrefix}_${namespace.value}',
        ),
      );
      namespaceServices[namespace] = StorageService(provider);
    }
    return StorageKernel(
      profile: StorageProfile(
        name: 'localdb_$keyspacePrefix',
        namespaces: [
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
      resolver: InMemoryStorageProfileResolver(
        namespaceServices: namespaceServices,
      ),
    );
  }

  Future<(StorageKernel, Directory)> buildFilesystemKernel({
    required String? name,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'mig_fs_${name ?? 'x'}_',
    );
    // One provider per namespace with isolated subdirectories.
    final namespaceServices = <StorageNamespace, StorageService>{};
    for (final namespace in [
      StorageNamespace.settings,
      StorageNamespace.projects,
    ]) {
      final namespaceDir = Directory('${directory.path}/${namespace.value}')
        ..createSync(recursive: true);
      final provider = FileSystemStorageProvider();
      await provider.initWithConfig(
        FileSystemConfig(
          filePathConfig: FilePathConfig.create(
            path: namespaceDir.path,
            macOSBookmarkData: MacOSBookmark.fromDirectory(namespaceDir),
          ),
        ),
      );
      namespaceServices[namespace] = StorageService(provider);
    }
    return (
      StorageKernel(
        profile: StorageProfile(
          name: 'fs_${name ?? 'x'}',
          namespaces: [
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
        resolver: InMemoryStorageProfileResolver(
          namespaceServices: namespaceServices,
        ),
      ),
      directory,
    );
  }

  Future<(StorageKernel, Directory)> buildGitOfflineKernel({
    required String? name,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'mig_git_${name ?? 'x'}_',
    );
    // One git repo per namespace with isolated subdirectories.
    final namespaceServices = <StorageNamespace, StorageService>{};
    for (final namespace in [
      StorageNamespace.settings,
      StorageNamespace.projects,
    ]) {
      final namespaceDir = Directory('${directory.path}/${namespace.value}')
        ..createSync(recursive: true);
      final provider = OfflineGitStorageProvider();
      await provider.initWithConfig(
        OfflineGitConfig(
          localPath: namespaceDir.path,
          authorName: 'Migration Test',
          authorEmail: 'migration@test.local',
        ),
      );
      namespaceServices[namespace] = StorageService(provider);
    }
    return (
      StorageKernel(
        profile: StorageProfile(
          name: 'git_${name ?? 'x'}',
          namespaces: [
            StorageNamespaceProfile(
              namespace: StorageNamespace.settings,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'offline-git',
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'offline-git',
            ),
          ],
        ),
        resolver: InMemoryStorageProfileResolver(
          namespaceServices: namespaceServices,
        ),
      ),
      directory,
    );
  }

  MigrationPlan planFor({
    required final String id,
    required final StorageKernel source,
    required final StorageKernel target,
  }) => MigrationPlan(
    id: id,
    sourceProfileHash: source.profile.name,
    targetProfileHash: target.profile.name,
    createdAt: DateTime.now().toUtc(),
  );

  group('migration scenario: local_db → filesystem', () {
    test(
      'one-shot import preserves all content with checksums verified',
      () async {
        final source = await buildLocalDbKernel(keyspacePrefix: 'mig_src_fs');
        // Seed heterogeneous data.
        await source.write(
          namespace: StorageNamespace.settings,
          path: 'settings/theme.json',
          content: '{"theme":"dark","fontSize":14}',
        );
        await source.write(
          namespace: StorageNamespace.projects,
          path: 'projects/alpha.json',
          content: '{"id":"alpha","title":"Project Alpha","tags":["a","b"]}',
        );
        await source.write(
          namespace: StorageNamespace.projects,
          path: 'projects/beta.json',
          content: '{"id":"beta","title":"Ünïcode 🌍 project"}',
        );
        await source.write(
          namespace: StorageNamespace.projects,
          path: 'notes/plain.txt',
          content: '',
        );

        final (target, directory) = await buildFilesystemKernel(name: 'dst');
        try {
          final manager = StorageProfileMigrationManager(
            sourceKernel: source,
            targetKernel: target,
          );
          final plan = planFor(
            id: 'localdb-to-fs-1',
            source: source,
            target: target,
          );

          final preparation = await manager.prepareMigration(plan: plan);
          expect(preparation.ok, isTrue, reason: preparation.issues.join('; '));

          final result = await manager.executeMigration(plan: plan);
          expect(result.ok, isTrue, reason: result.message);
          expect(result.status, MigrationStatus.completed);

          // Verify every file landed byte-identical.
          final expected = <(StorageNamespace, String, String)>[
            (
              StorageNamespace.settings,
              'settings/theme.json',
              '{"theme":"dark","fontSize":14}',
            ),
            (
              StorageNamespace.projects,
              'projects/alpha.json',
              '{"id":"alpha","title":"Project Alpha","tags":["a","b"]}',
            ),
            (
              StorageNamespace.projects,
              'projects/beta.json',
              '{"id":"beta","title":"Ünïcode 🌍 project"}',
            ),
            (StorageNamespace.projects, 'notes/plain.txt', ''),
          ];
          for (final spec in expected) {
            final content = await target.read(
              namespace: spec.$1,
              path: spec.$2,
            );
            expect(content, spec.$3, reason: '${spec.$2} mismatch');
          }
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test('re-running a completed migration is a no-op (idempotent)', () async {
      final source = await buildLocalDbKernel(keyspacePrefix: 'mig_idem_src');
      await source.write(
        namespace: StorageNamespace.settings,
        path: 'settings/app.json',
        content: '{"v":1}',
      );

      final (target, directory) = await buildFilesystemKernel(name: 'idem');
      try {
        final manager = StorageProfileMigrationManager(
          sourceKernel: source,
          targetKernel: target,
        );
        final plan = planFor(id: 'idem-1', source: source, target: target);

        final first = await manager.executeMigration(plan: plan);
        expect(first.ok, isTrue);

        final second = await manager.executeMigration(plan: plan);
        expect(second.ok, isTrue);
        expect(second.status, MigrationStatus.completed);

        final content = await target.read(
          namespace: StorageNamespace.settings,
          path: 'settings/app.json',
        );
        expect(content, '{"v":1}');
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('migration scenario: local_db → git_offline', () {
    test('direct import into versioned storage commits cleanly', () async {
      final source = await buildLocalDbKernel(keyspacePrefix: 'mig_src_git');
      await source.write(
        namespace: StorageNamespace.settings,
        path: 'settings/prefs.json',
        content: '{"notifications":true}',
      );
      await source.write(
        namespace: StorageNamespace.projects,
        path: 'projects/gamma.json',
        content: '{"id":"gamma"}',
      );

      final (target, directory) = await buildGitOfflineKernel(name: 'dst');
      try {
        final manager = StorageProfileMigrationManager(
          sourceKernel: source,
          targetKernel: target,
        );
        final plan = planFor(
          id: 'localdb-to-git-1',
          source: source,
          target: target,
        );

        final result = await manager.executeMigration(plan: plan);
        expect(result.ok, isTrue, reason: result.message);

        expect(
          await target.read(
            namespace: StorageNamespace.settings,
            path: 'settings/prefs.json',
          ),
          '{"notifications":true}',
        );
        expect(
          await target.read(
            namespace: StorageNamespace.projects,
            path: 'projects/gamma.json',
          ),
          '{"id":"gamma"}',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('migration scenario: filesystem → git_offline → local_db chain', () {
    test('data survives two consecutive backend hops', () async {
      final (origin, originDir) = await buildFilesystemKernel(name: 'chain0');
      const documents = <(StorageNamespace, String, String)>[
        (
          StorageNamespace.settings,
          'settings/config.json',
          '{"lang":"en","region":"EU"}',
        ),
        (
          StorageNamespace.projects,
          'projects/delta.json',
          '{"id":"delta","steps":3}',
        ),
      ];
      for (final doc in documents) {
        await origin.write(namespace: doc.$1, path: doc.$2, content: doc.$3);
      }

      try {
        // Hop 1: filesystem → git_offline.
        final (gitTarget, gitDir) = await buildGitOfflineKernel(name: 'chain1');
        try {
          final hop1 =
              StorageProfileMigrationManager(
                sourceKernel: origin,
                targetKernel: gitTarget,
              ).executeMigration(
                plan: planFor(
                  id: 'chain-hop1',
                  source: origin,
                  target: gitTarget,
                ),
              );
          final hop1Result = await hop1;
          expect(hop1Result.ok, isTrue, reason: hop1Result.message);

          // Hop 2: git_offline → local_db.
          final dbTarget = await buildLocalDbKernel(
            keyspacePrefix: 'mig_chain_dst',
          );
          final hop2 =
              StorageProfileMigrationManager(
                sourceKernel: gitTarget,
                targetKernel: dbTarget,
              ).executeMigration(
                plan: planFor(
                  id: 'chain-hop2',
                  source: gitTarget,
                  target: dbTarget,
                ),
              );
          final hop2Result = await hop2;
          expect(hop2Result.ok, isTrue, reason: hop2Result.message);

          for (final doc in documents) {
            final content = await dbTarget.read(
              namespace: doc.$1,
              path: doc.$2,
            );
            expect(content, doc.$3, reason: '${doc.$2} mismatch');
          }
        } finally {
          await gitDir.delete(recursive: true);
        }
      } finally {
        await originDir.delete(recursive: true);
      }
    });
  });

  group('migration conflict handling', () {
    test('overwrite=false pauses on existing divergent target file', () async {
      final source = await buildLocalDbKernel(keyspacePrefix: 'mig_conf_src');
      await source.write(
        namespace: StorageNamespace.settings,
        path: 'settings/shared.json',
        content: '{"source":"new-data"}',
      );

      final (target, directory) = await buildFilesystemKernel(name: 'conf');
      try {
        // Pre-existing divergent content at the same path.
        await target.write(
          namespace: StorageNamespace.settings,
          path: 'settings/shared.json',
          content: '{"source":"old-data"}',
        );

        final manager = StorageProfileMigrationManager(
          sourceKernel: source,
          targetKernel: target,
        );
        final plan = planFor(
          id: 'conflict-1',
          source: source,
          target: target,
        ).copyWith(metadata: {'overwrite': false});

        final result = await manager.executeMigration(plan: plan);
        // The operation must not silently lose either side.
        expect(result.status, isNot(MigrationStatus.completed));

        // Original target content must be intact (no silent overwrite).
        final preserved = await target.read(
          namespace: StorageNamespace.settings,
          path: 'settings/shared.json',
        );
        expect(preserved, '{"source":"old-data"}');

        // Now resolve by allowing overwrite.
        final resolvedPlan = plan.copyWith(metadata: {'overwrite': true});
        final resolved = await manager.executeMigration(plan: resolvedPlan);
        expect(resolved.ok, isTrue, reason: resolved.message);

        final overwritten = await target.read(
          namespace: StorageNamespace.settings,
          path: 'settings/shared.json',
        );
        expect(overwritten, '{"source":"new-data"}');
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}

/// Shared in-memory LocalDb so multiple providers can coexist per test.
class _SharedInMemoryLocalDb implements LocalDbI {
  final Map<String, bool> _bools = {};
  final Map<String, int> _ints = {};
  final Map<String, String> _strings = {};
  final Map<String, Map<String, dynamic>> _maps = {};
  final Map<String, List<String>> _stringLists = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> clear() async {
    _bools.clear();
    _ints.clear();
    _strings.clear();
    _maps.clear();
    _stringLists.clear();
  }

  @override
  Future<void> clearKey({required final String key}) async {
    _bools.remove(key);
    _ints.remove(key);
    _strings.remove(key);
    _maps.remove(key);
    _stringLists.remove(key);
  }

  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) async => _bools[key] ?? defaultValue;

  @override
  Future<int> getInt({
    required final String key,
    final int defaultValue = 0,
  }) async => _ints[key] ?? defaultValue;

  @override
  Future<Map<String, dynamic>> getMap(final String key) async =>
      Map<String, dynamic>.from(_maps[key] ?? const {});

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) async {
    final values = _stringLists[key];
    if (values == null) return defaultValue;
    return values
        .map((final item) => _maps[item])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from);
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) async => _strings[key] ?? defaultValue;

  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
  }) async => List<String>.from(_stringLists[key] ?? defaultValue);

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic> p1) fromJson,
    required final T defaultValue,
  }) async => fromJson(await getMap(key)) ?? defaultValue;

  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic> p1) fromJson,
    final List<T> defaultValue = const [],
  }) async {
    final values = await getMapIterable(key: key);
    if (values.isEmpty) return defaultValue;
    return values.map(fromJson);
  }

  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) async {
    _bools[key] = value;
  }

  @override
  Future<void> setInt({required final String key, final int value = 0}) async {
    _ints[key] = value;
  }

  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) async {
    _maps[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async {
    final ids = <String>[];
    for (var index = 0; index < value.length; index++) {
      final id = '$key#$index';
      _maps[id] = Map<String, dynamic>.from(value[index]);
      ids.add(id);
    }
    _stringLists[key] = ids;
  }

  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) async {
    _strings[key] = value;
  }

  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) async {
    _stringLists[key] = List<String>.from(value);
  }

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    await setMap(key: key, value: toJson(value));
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    await setMapList(key: key, value: value.map(toJson).toList());
  }
}
