import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

import 'cloudkit_storage_provider.dart';

/// Registers CloudKit provider in the universal storage registry.
void registerUniversalStorageCloudKit({final CloudKitBridge? bridge}) {
  if (bridge != null) {
    CloudKitBridgePlatform.instance = bridge;
  }

  StorageProviderRegistry.register<CloudKitConfig>(
    () => CloudKitStorageProvider(),
  );
}
