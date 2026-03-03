// ignore_for_file: avoid_print

import 'package:universal_io/io.dart';
import 'package:universal_storage_cloudkit/universal_storage_cloudkit.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

const _isWeb =
    bool.fromEnvironment('dart.library.js_interop') ||
    bool.fromEnvironment('dart.library.js');

Future<void> main() async {
  registerUniversalStorageCloudKit();

  final remoteOnlyService = await StorageFactory.createCloudKit(
    CloudKitConfig(
      containerId: 'iCloud.com.example.app',
      environment: CloudKitEnvironment.development,
      dataMode: CloudKitDataMode.remoteOnly,
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
        webApiToken: _isWeb ? 'replace-with-web-api-token' : null,
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

    final profile = StorageProfile(
      name: 'cloudkit_profile_v1',
      namespaces: const <StorageNamespaceProfile>[
        StorageNamespaceProfile(
          namespace: StorageNamespace.settings,
          policy: StoragePolicy.remoteFirst,
          localEngineId: 'cloudkit',
          remoteEngineId: 'cloudkit',
          defaultFileExtension: '.json',
        ),
        StorageNamespaceProfile(
          namespace: StorageNamespace.projects,
          policy: StoragePolicy.optimisticSync,
          localEngineId: 'cloudkit',
          remoteEngineId: 'cloudkit',
          defaultFileExtension: '.json',
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
