import 'package:test/test.dart';
import 'package:universal_storage_cloudkit/universal_storage_cloudkit.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'cloudkit_storage_provider_test.dart' show FakeCloudKitBridge;

void main() {
  storageProviderConformanceTests(
    'CloudKitStorageProvider (fake bridge)',
    create: () async {
      final provider = CloudKitStorageProvider(bridge: FakeCloudKitBridge());
      await provider.initWithConfig(
        CloudKitConfig(containerId: 'iCloud.com.example.conformance'),
      );
      return provider;
    },
    supportsSync: true,
    // CloudKit v1 explicitly does not support restore().
    supportsRestore: false,
  );
}
