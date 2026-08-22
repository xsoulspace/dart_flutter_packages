import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_local_db/universal_storage_local_db.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// Migration and sync benchmarks across real backends.
///
/// These are informational benchmarks (not hard gates) measuring:
/// - migration throughput per backend pair (files/sec)
/// - kernel write p50/p95 latency per local backend
/// - outbox replay throughput
void main() {
  const fileCounts = [10, 100];

  Future<StorageKernel> buildLocalDbKernel({
    required final String keyspacePrefix,
  }) async {
    final namespaceServices = <StorageNamespace, StorageService>{};
    for (final namespace in [
      StorageNamespace.settings,
      StorageNamespace.projects,
    ]) {
      final provider = LocalDbStorageProvider(localDb: _BenchInMemoryLocalDb());
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
      'bench_fs_${name ?? 'x'}_',
    );
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
      'bench_git_${name ?? 'x'}_',
    );
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
          authorName: 'Benchmark',
          authorEmail: 'benchmark@test.local',
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
            ),
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
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

  String payloadFor(final int index) =>
      '{"id":"doc-$index","title":"Document $index",'
      '"body":"${'lorem ipsum ' * 20}","index":$index}';

  Duration percentile(final List<Duration> samples, final double p) {
    if (samples.isEmpty) return Duration.zero;
    final sorted = samples.toList()..sort();
    final index = ((sorted.length - 1) * p).ceil().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  group('migration benchmarks', () {
    const gitTimeout = Timeout(Duration(minutes: 5));
    for (final count in fileCounts) {
      test('local_db → filesystem: $count files', () async {
        final source = await buildLocalDbKernel(
          keyspacePrefix: 'bench_src_fs_$count',
        );
        final (target, directory) = await buildFilesystemKernel(
          name: 'bench$count',
        );
        try {
          for (var i = 0; i < count; i++) {
            await source.write(
              namespace: i.isEven
                  ? StorageNamespace.settings
                  : StorageNamespace.projects,
              path: 'docs/doc-$i.json',
              content: payloadFor(i),
            );
          }

          final manager = StorageProfileMigrationManager(
            sourceKernel: source,
            targetKernel: target,
          );
          final stopwatch = Stopwatch()..start();
          final result = await manager.executeMigration(
            plan: MigrationPlan(
              id: 'bench-fs-$count',
              sourceProfileHash: source.profile.name,
              targetProfileHash: target.profile.name,
              createdAt: DateTime.now().toUtc(),
            ),
          );
          stopwatch.stop();

          expect(result.ok, isTrue, reason: result.message);
          // ignore: avoid_print
          print(
            '[bench] local_db→filesystem $count files: '
            '${stopwatch.elapsedMilliseconds}ms '
            '(${(count / (stopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(1)} files/sec)',
          );
        } finally {
          await directory.delete(recursive: true);
        }
      });

      test('local_db → git_offline: $count files', () async {
        final source = await buildLocalDbKernel(
          keyspacePrefix: 'bench_src_git_$count',
        );
        final (target, directory) = await buildGitOfflineKernel(
          name: 'bench$count',
        );
        try {
          for (var i = 0; i < count; i++) {
            await source.write(
              namespace: i.isEven
                  ? StorageNamespace.settings
                  : StorageNamespace.projects,
              path: 'docs/doc-$i.json',
              content: payloadFor(i),
            );
          }

          final manager = StorageProfileMigrationManager(
            sourceKernel: source,
            targetKernel: target,
          );
          final stopwatch = Stopwatch()..start();
          final result = await manager.executeMigration(
            plan: MigrationPlan(
              id: 'bench-git-$count',
              sourceProfileHash: source.profile.name,
              targetProfileHash: target.profile.name,
              createdAt: DateTime.now().toUtc(),
            ),
          );
          stopwatch.stop();

          expect(result.ok, isTrue, reason: result.message);
          // ignore: avoid_print
          print(
            '[bench] local_db→git_offline $count files: '
            '${stopwatch.elapsedMilliseconds}ms '
            '(${(count / (stopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(1)} files/sec)',
          );
        } finally {
          await directory.delete(recursive: true);
        }
      }, timeout: gitTimeout);
    }
  });

  group('write latency benchmarks', () {
    for (final entry in {
      'local_db': 'bench_lat_db',
      'filesystem': 'bench_lat_fs',
    }.entries) {
      test('${entry.key}: 100 writes p50/p95', () async {
        final kernel = await buildLocalDbKernel(keyspacePrefix: entry.value);
        final latencies = <Duration>[];
        for (var i = 0; i < 100; i++) {
          final stopwatch = Stopwatch()..start();
          await kernel.write(
            namespace: StorageNamespace.settings,
            path: 'lat/file-$i.json',
            content: payloadFor(i),
          );
          stopwatch.stop();
          latencies.add(stopwatch.elapsed);
        }
        // ignore: avoid_print
        print(
          '[bench] ${entry.key} write p50=${percentile(latencies, 0.5).inMicroseconds}µs '
          'p95=${percentile(latencies, 0.95).inMicroseconds}µs '
          '(n=100)',
        );
      });
    }

    test('filesystem: 100 writes p50/p95', () async {
      final (kernel, directory) = await buildFilesystemKernel(name: 'lat');
      try {
        final latencies = <Duration>[];
        for (var i = 0; i < 100; i++) {
          final stopwatch = Stopwatch()..start();
          await kernel.write(
            namespace: StorageNamespace.settings,
            path: 'lat/file-$i.json',
            content: payloadFor(i),
          );
          stopwatch.stop();
          latencies.add(stopwatch.elapsed);
        }
        // ignore: avoid_print
        print(
          '[bench] filesystem write p50=${percentile(latencies, 0.5).inMicroseconds}µs '
          'p95=${percentile(latencies, 0.95).inMicroseconds}µs '
          '(n=100)',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('git_offline: 100 writes p50/p95', () async {
      final (kernel, directory) = await buildGitOfflineKernel(name: 'lat');
      try {
        final latencies = <Duration>[];
        for (var i = 0; i < 100; i++) {
          final stopwatch = Stopwatch()..start();
          await kernel.write(
            namespace: StorageNamespace.settings,
            path: 'lat/file-$i.json',
            content: payloadFor(i),
          );
          stopwatch.stop();
          latencies.add(stopwatch.elapsed);
        }
        // ignore: avoid_print
        print(
          '[bench] git_offline write p50=${percentile(latencies, 0.5).inMilliseconds}ms '
          'p95=${percentile(latencies, 0.95).inMilliseconds}ms '
          '(n=100, includes git commit per write)',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('outbox replay benchmark', () {
    test('enqueue + replay 100 entries against offline-git', () async {
      final (kernel, directory) = await buildGitOfflineKernel(name: 'outbox');
      try {
        final enqueueStart = Stopwatch()..start();
        for (var i = 0; i < 100; i++) {
          await kernel.write(
            namespace: StorageNamespace.projects,
            path: 'outbox/file-$i.json',
            content: payloadFor(i),
          );
        }
        enqueueStart.stop();

        final replayStopwatch = Stopwatch()..start();
        await kernel.sync(namespace: StorageNamespace.projects);
        replayStopwatch.stop();

        final outbox = await kernel.outboxSnapshot(StorageNamespace.projects);
        expect(outbox, isEmpty, reason: 'outbox should drain after sync');

        // ignore: avoid_print
        print(
          '[bench] outbox enqueue 100 entries: ${enqueueStart.elapsedMilliseconds}ms; '
          'replay: ${replayStopwatch.elapsedMilliseconds}ms '
          '(${(100 / (replayStopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(1)} entries/sec)',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}

class _BenchInMemoryLocalDb implements LocalDbI {
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
