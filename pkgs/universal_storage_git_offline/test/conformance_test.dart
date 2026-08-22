import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  storageProviderConformanceTests(
    'OfflineGitStorageProvider',
    create: () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'conformance_git_',
      );
      final provider = OfflineGitStorageProvider();
      await provider.initWithConfig(
        OfflineGitConfig(
          localPath: tempDirectory.path,
          authorName: 'Conformance',
          authorEmail: 'conformance@example.com',
        ),
      );
      return provider;
    },
    supportsSync: true,
  );
}
