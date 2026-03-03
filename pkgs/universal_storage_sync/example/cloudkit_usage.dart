// ignore_for_file: avoid_print

import 'package:universal_io/io.dart';
import 'package:universal_storage_cloudkit/universal_storage_cloudkit.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

const _isWeb = identical(0, 0.0);

Future<void> main() async {
  if (_isWeb) {
    registerUniversalStorageCloudKit();
  } else {
    // Pure Dart example fallback: keep sample runnable without Apple bridge
    // package. In Flutter iOS/macOS apps, registerCloudKitAppleBridge().
    registerUniversalStorageCloudKit(bridge: _ExampleCloudKitBridge());
  }

  final remoteOnlyService = await StorageFactory.createCloudKit(
    CloudKitConfig(
      containerId: 'iCloud.com.example.app',
      webApiToken: _isWeb ? 'replace-with-web-api-token' : null,
    ),
  );

  await remoteOnlyService.saveFile('settings/app.json', '{"mode":"remote"}');
  await remoteOnlyService.syncRemote();

  if (!_isWeb && (Platform.isIOS || Platform.isMacOS)) {
    final mirrorRoot = await Directory.systemTemp.createTemp(
      'cloudkit_local_mirror_example_',
    );

    final localMirrorService = await StorageFactory.createCloudKit(
      CloudKitConfig(
        containerId: 'iCloud.com.example.app',
        dataMode: CloudKitDataMode.localMirror,
        localMirrorConfig: FileSystemConfig(
          filePathConfig: FilePathConfig.create(
            path: mirrorRoot.path,
            macOSBookmarkData: MacOSBookmark.fromDirectory(mirrorRoot),
          ),
        ),
      ),
    );

    await localMirrorService.saveFile('projects/p1.json', '{"id":"p1"}');
    await localMirrorService.syncRemote(
      pullMergeStrategy: ConflictResolutionStrategy.lastWriteWins.name,
      pushConflictStrategy: ConflictResolutionStrategy.clientAlwaysRight.name,
    );

    const profile = StorageProfile(
      name: 'cloudkit_profile_v1',
      namespaces: <StorageNamespaceProfile>[
        StorageNamespaceProfile(
          namespace: StorageNamespace.settings,
          policy: StoragePolicy.remoteFirst,
          localEngineId: 'cloudkit',
          remoteEngineId: 'cloudkit',
        ),
        StorageNamespaceProfile(
          namespace: StorageNamespace.projects,
          policy: StoragePolicy.optimisticSync,
          localEngineId: 'cloudkit',
          remoteEngineId: 'cloudkit',
        ),
      ],
    );

    print('CloudKit profile template: ${profile.toJson()}');
  } else if (_isWeb) {
    print(
      'Web branch active: provide CloudKit JS + webApiToken before startup.',
    );
  } else {
    print('CloudKit native branch skipped: current platform is not iOS/macOS.');
  }
}

class _ExampleCloudKitBridge implements CloudKitBridge {
  final Map<String, CloudKitRecord> _recordsByPath = <String, CloudKitRecord>{};

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {}

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async =>
      _recordsByPath[path];

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    _recordsByPath[record.path] = record;
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    _recordsByPath.removeWhere(
      (final _, final record) => record.recordName == recordName,
    );
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    if (pathPrefix.isEmpty) {
      return _recordsByPath.values.toList(growable: false);
    }

    final normalizedPrefix = '$pathPrefix/';
    return _recordsByPath.values
        .where(
          (final record) =>
              record.path == pathPrefix ||
              record.path.startsWith(normalizedPrefix),
        )
        .toList(growable: false);
  }

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async =>
      CloudKitDelta(
        updatedRecords: _recordsByPath.values.toList(growable: false),
        nextServerChangeToken: serverChangeToken,
      );

  @override
  Future<void> dispose() async {}
}
