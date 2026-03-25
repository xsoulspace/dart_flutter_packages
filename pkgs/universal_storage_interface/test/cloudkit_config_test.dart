import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  group('CloudKitConfig', () {
    test('uses expected defaults', () {
      final config = CloudKitConfig(containerId: 'iCloud.com.example.app');

      expect(config.environment, CloudKitEnvironment.development);
      expect(config.databaseScope, CloudKitDatabaseScope.privateDb);
      expect(config.dataMode, CloudKitDataMode.remoteOnly);
      expect(config.zoneName, 'UniversalStorageZone');
      expect(config.recordType, 'USFile');
      expect(config.maxInlineBytes, 262144);
      expect(config.webApiToken, isNull);
    });

    test('requires localMirrorConfig for localMirror mode', () {
      expect(
        () => CloudKitConfig(
          containerId: 'iCloud.com.example.app',
          dataMode: CloudKitDataMode.localMirror,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts localMirror mode with filesystem config', () async {
      final tempDir = await Directory.systemTemp.createTemp('cloudkit_cfg_');
      try {
        final config = CloudKitConfig(
          containerId: 'iCloud.com.example.app',
          dataMode: CloudKitDataMode.localMirror,
          localMirrorConfig: FileSystemConfig(
            filePathConfig: FilePathConfig.create(
              path: tempDir.path,
              macOSBookmarkData: MacOSBookmark.fromDirectory(tempDir),
            ),
          ),
        );

        expect(config.dataMode, CloudKitDataMode.localMirror);
        expect(config.localMirrorConfig, isNotNull);
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('rejects recursive fallback cloudkit config', () {
      final fallback = CloudKitConfig(
        containerId: 'iCloud.com.example.fallback',
      );

      expect(
        () => CloudKitConfig(
          containerId: 'iCloud.com.example.app',
          fallbackConfig: fallback,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toMap includes cloudkit fields', () {
      final config = CloudKitConfig(
        containerId: 'iCloud.com.example.app',
        webApiToken: 'token',
      );

      final map = config.toMap();
      expect(map['containerId'], 'iCloud.com.example.app');
      expect(map['environment'], 'development');
      expect(map['databaseScope'], 'privateDb');
      expect(map['dataMode'], 'remoteOnly');
      expect(map['webApiToken'], 'token');
    });
  });
}
