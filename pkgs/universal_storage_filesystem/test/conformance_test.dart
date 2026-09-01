import 'dart:io';

import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  storageProviderConformanceTests(
    'FileSystemStorageProvider',
    create: () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'conformance_fs_',
      );
      final provider = FileSystemStorageProvider();
      await provider.initWithConfig(
        FileSystemConfig(
          filePathConfig: FilePathConfig.create(
            path: tempDirectory.path,
            macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
          ),
        ),
      );
      return provider;
    },
  );
}
