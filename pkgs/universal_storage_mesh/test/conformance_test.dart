import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';

void main() {
  storageProviderConformanceTests(
    'MeshStorageProvider',
    create: () async {
      final dir = await Directory.systemTemp.createTemp('mesh_conf_');
      final provider = MeshStorageProvider();
      await provider.initWithConfig(
        MeshStorageConfig(storePath: dir.path, peerId: 'solo-device'),
      );
      return provider;
    },
    supportsSync: true,
    supportsRestore: false,
  );
}
