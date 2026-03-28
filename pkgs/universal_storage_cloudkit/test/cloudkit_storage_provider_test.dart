import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_cloudkit/universal_storage_cloudkit.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  group('CloudKitStorageProvider remoteOnly', () {
    late _FakeCloudKitBridge bridge;
    late CloudKitStorageProvider provider;

    setUp(() {
      bridge = _FakeCloudKitBridge();
      provider = CloudKitStorageProvider(bridge: bridge);
    });

    test('CRUD and list semantics work via remote bridge', () async {
      await provider.initWithConfig(
        CloudKitConfig(containerId: 'iCloud.com.example.app'),
      );

      expect(provider.supportsSync, isTrue);

      await provider.createFile('docs/readme.md', 'hello');
      expect(await provider.getFile('docs/readme.md'), equals('hello'));

      final list = await provider.listDirectory('docs');
      expect(list.map((final e) => e.name), contains('readme.md'));

      await provider.updateFile('docs/readme.md', 'updated');
      expect(await provider.getFile('docs/readme.md'), equals('updated'));

      await provider.deleteFile('docs/readme.md');
      expect(await provider.getFile('docs/readme.md'), isNull);

      final missing = await provider.listDirectory('missing');
      expect(missing, isEmpty);
    });

    test(
      'sync in remoteOnly fetches delta without local mirror writes',
      () async {
        await provider.initWithConfig(
          CloudKitConfig(containerId: 'iCloud.com.example.app'),
        );
        bridge.nextDelta = const CloudKitDelta(
          nextServerChangeToken: 'token-1',
        );

        await provider.sync();

        expect(bridge.fetchChangesCalls, equals(1));
      },
    );

    test('oversize payload maps to ConfigurationException', () async {
      await provider.initWithConfig(
        CloudKitConfig(
          containerId: 'iCloud.com.example.app',
          maxInlineBytes: 4,
        ),
      );

      await expectLater(
        () => provider.createFile('big.txt', '12345'),
        throwsA(isA<ConfigurationException>()),
      );
    });
  });

  group('CloudKitStorageProvider localMirror', () {
    late _FakeCloudKitBridge bridge;
    late Directory tempDir;
    late CloudKitStorageProvider provider;

    setUp(() async {
      bridge = _FakeCloudKitBridge();
      tempDir = await Directory.systemTemp.createTemp('cloudkit_local_mirror_');

      provider = CloudKitStorageProvider(bridge: bridge);
      await provider.initWithConfig(
        CloudKitConfig(
          containerId: 'iCloud.com.example.app',
          dataMode: CloudKitDataMode.localMirror,
          localMirrorConfig: FileSystemConfig(
            filePathConfig: FilePathConfig.create(
              path: tempDir.path,
              macOSBookmarkData: MacOSBookmark.fromDirectory(tempDir),
            ),
          ),
        ),
      );
    });

    tearDown(() async {
      await provider.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'sync performs pull-then-push and persists token state file',
      () async {
        await provider.createFile('notes/a.txt', 'local-content');
        await File(
          '${tempDir.path}/notes/a.txt',
        ).writeAsString('locally-edited');

        bridge.nextDelta = const CloudKitDelta(
          nextServerChangeToken: 'after-sync-token',
        );

        await provider.sync();

        final fetchIndex = bridge.callLog.indexOf('fetchChanges');
        final saveIndex = bridge.callLog.indexOf('saveRecord:notes/a.txt');
        expect(fetchIndex, isNonNegative);
        expect(saveIndex, isNonNegative);
        expect(fetchIndex, lessThan(saveIndex));
        expect(bridge.recordsByPath.containsKey('notes/a.txt'), isTrue);

        final stateFile = File('${tempDir.path}/.us/cloudkit/state_v1.json');
        expect(stateFile.existsSync(), isTrue);
        final content = await stateFile.readAsString();
        expect(content, contains('after-sync-token'));
      },
    );

    test('pull applies remote updates to local mirror', () async {
      bridge.recordsByPath['remote/file.json'] = _fakeRecord(
        path: 'remote/file.json',
        content: '{"v":1}',
      );
      bridge.nextDelta = CloudKitDelta(
        updatedRecords: <CloudKitRecord>[
          bridge.recordsByPath['remote/file.json']!,
        ],
      );

      await provider.sync();

      expect(await provider.getFile('remote/file.json'), equals('{"v":1}'));
    });

    test('manual conflict strategy throws SyncConflictException', () async {
      await provider.createFile('conflict.txt', 'local');
      bridge.nextDelta = CloudKitDelta(
        updatedRecords: <CloudKitRecord>[
          _fakeRecord(path: 'conflict.txt', content: 'remote'),
        ],
      );

      await expectLater(
        () => provider.sync(pullMergeStrategy: 'manualResolution'),
        throwsA(isA<SyncConflictException>()),
      );
    });

    test(
      'clientAlwaysRight keeps local and overwrites remote update',
      () async {
        await provider.createFile('conflict_keep_local.txt', 'local-v1');

        bridge.recordsByPath['conflict_keep_local.txt'] = _fakeRecord(
          path: 'conflict_keep_local.txt',
          content: 'remote-v2',
        );
        bridge.nextDelta = CloudKitDelta(
          updatedRecords: <CloudKitRecord>[
            bridge.recordsByPath['conflict_keep_local.txt']!,
          ],
        );

        await provider.sync(
          pullMergeStrategy: ConflictResolutionStrategy.clientAlwaysRight.name,
          pushConflictStrategy:
              ConflictResolutionStrategy.clientAlwaysRight.name,
        );

        expect(await provider.getFile('conflict_keep_local.txt'), 'local-v1');
        expect(
          bridge.recordsByPath['conflict_keep_local.txt']?.content,
          'local-v1',
        );
      },
    );

    test(
      'clientAlwaysRight keeps local file and recreates remote after deletion',
      () async {
        await provider.createFile('deleted_remote.txt', 'local-v1');

        bridge.nextDelta = const CloudKitDelta(
          deletedPaths: <String>['deleted_remote.txt'],
        );
        bridge.recordsByPath.remove('deleted_remote.txt');

        await provider.sync(
          pullMergeStrategy: ConflictResolutionStrategy.clientAlwaysRight.name,
          pushConflictStrategy:
              ConflictResolutionStrategy.clientAlwaysRight.name,
        );

        expect(await provider.getFile('deleted_remote.txt'), 'local-v1');
        expect(bridge.recordsByPath['deleted_remote.txt']?.content, 'local-v1');
      },
    );

    test('lastWriteWins keeps newer local content and pushes', () async {
      await provider.createFile('lww.txt', 'local-newer');

      bridge.recordsByPath['lww.txt'] = _fakeRecord(
        path: 'lww.txt',
        content: 'remote-older',
        updatedAt: DateTime.utc(2000),
      );
      bridge.nextDelta = CloudKitDelta(
        updatedRecords: <CloudKitRecord>[bridge.recordsByPath['lww.txt']!],
      );

      await provider.sync(
        pullMergeStrategy: ConflictResolutionStrategy.lastWriteWins.name,
        pushConflictStrategy: ConflictResolutionStrategy.lastWriteWins.name,
      );

      expect(await provider.getFile('lww.txt'), 'local-newer');
      expect(bridge.recordsByPath['lww.txt']?.content, 'local-newer');
    });

    test(
      'lastWriteWins applies newer remote content after push conflict',
      () async {
        await provider.createFile('lww_remote_newer.txt', 'local-initial');
        await File(
          '${tempDir.path}/lww_remote_newer.txt',
        ).writeAsString('local-edited');

        bridge.recordsByPath['lww_remote_newer.txt'] = _fakeRecord(
          path: 'lww_remote_newer.txt',
          content: 'remote-newer',
          updatedAt: DateTime.now().toUtc(),
          changeTag: 'remote-v2',
        );
        bridge.conflictOnNextSavePaths.add('lww_remote_newer.txt');

        await provider.sync(
          pullMergeStrategy: ConflictResolutionStrategy.lastWriteWins.name,
          pushConflictStrategy: ConflictResolutionStrategy.lastWriteWins.name,
        );

        expect(await provider.getFile('lww_remote_newer.txt'), 'remote-newer');
        expect(
          bridge.recordsByPath['lww_remote_newer.txt']?.content,
          'remote-newer',
        );
      },
    );
  });

  group('CloudKitStorageProvider fallback', () {
    test(
      'uses fallback provider when bridge init fails and fallback configured',
      () async {
        final bridge = _FakeCloudKitBridge()..throwOnInitialize = true;
        final fallbackDir = await Directory.systemTemp.createTemp(
          'cloudkit_fallback_',
        );

        final provider = CloudKitStorageProvider(
          bridge: bridge,
          fallbackResolver: (final config) {
            if (config is FileSystemConfig) {
              return FileSystemStorageProvider();
            }
            throw ArgumentError('Unexpected fallback config: $config');
          },
        );

        await provider.initWithConfig(
          CloudKitConfig(
            containerId: 'iCloud.com.example.app',
            fallbackConfig: FileSystemConfig(
              filePathConfig: FilePathConfig.create(
                path: fallbackDir.path,
                macOSBookmarkData: MacOSBookmark.fromDirectory(fallbackDir),
              ),
            ),
          ),
        );

        await provider.createFile('a.txt', 'fallback-content');
        expect(await provider.getFile('a.txt'), equals('fallback-content'));

        await provider.dispose();
        if (fallbackDir.existsSync()) {
          await fallbackDir.delete(recursive: true);
        }
      },
    );

    test('throws unsupported error when no fallback configured', () async {
      final bridge = _FakeCloudKitBridge()..throwOnInitialize = true;
      final provider = CloudKitStorageProvider(bridge: bridge);

      await expectLater(
        () => provider.initWithConfig(
          CloudKitConfig(containerId: 'iCloud.com.example.app'),
        ),
        throwsA(isA<UnsupportedOperationException>()),
      );
    });
  });

  group('registerUniversalStorageCloudKit', () {
    test(
      'registers CloudKitConfig factory in StorageProviderRegistry',
      () async {
        final bridge = _FakeCloudKitBridge();
        registerUniversalStorageCloudKit(bridge: bridge);

        final service = await StorageFactory.createCloudKit(
          CloudKitConfig(containerId: 'iCloud.com.example.app'),
        );

        expect(service.provider, isA<CloudKitStorageProvider>());
        await service.provider.dispose();
        StorageProviderRegistry.unregister<CloudKitConfig>();
      },
    );
  });
}

class _FakeCloudKitBridge implements CloudKitBridge {
  final Map<String, CloudKitRecord> recordsByPath = <String, CloudKitRecord>{};
  final List<String> callLog = <String>[];
  final Set<String> conflictOnNextSavePaths = <String>{};

  CloudKitDelta nextDelta = CloudKitDelta.empty();
  int fetchChangesCalls = 0;
  bool throwOnInitialize = false;

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    callLog.add('initialize');
    if (throwOnInitialize) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit unavailable on this platform',
      );
    }
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async {
    callLog.add('fetchRecordByPath:$path');
    return recordsByPath[path];
  }

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    callLog.add('saveRecord:${record.path}');
    if (conflictOnNextSavePaths.remove(record.path)) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.conflict,
        message: 'Simulated conflict',
      );
    }
    recordsByPath[record.path] = record;
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    callLog.add('deleteRecord:$recordName');
    final toDelete = recordsByPath.entries
        .where((final entry) => entry.value.recordName == recordName)
        .map((final entry) => entry.key)
        .toList(growable: false);
    for (final path in toDelete) {
      recordsByPath.remove(path);
    }
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    callLog.add('queryByPathPrefix:$pathPrefix');
    if (pathPrefix.isEmpty) {
      return recordsByPath.values.toList(growable: false);
    }

    final prefix = '$pathPrefix/';
    return recordsByPath.values
        .where(
          (final record) =>
              record.path == pathPrefix || record.path.startsWith(prefix),
        )
        .toList(growable: false);
  }

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async {
    callLog.add('fetchChanges');
    fetchChangesCalls += 1;
    return nextDelta;
  }

  @override
  Future<void> dispose() async {
    callLog.add('dispose');
  }
}

CloudKitRecord _fakeRecord({
  required final String path,
  required final String content,
  final DateTime? updatedAt,
  final String? changeTag,
}) => CloudKitRecord(
  recordName: sha256Hex(path),
  path: path,
  content: content,
  checksum: normalizedSha256Hex(content),
  size: content.length,
  updatedAt: updatedAt ?? DateTime.now().toUtc(),
  changeTag: changeTag,
);
