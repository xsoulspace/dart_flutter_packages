import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

/// Normalized client contract used by CloudKit web bridge.
abstract interface class CloudKitWebClient {
  Future<void> initialize(final CloudKitBridgeConfig config);
  Future<CloudKitRecord?> fetchRecordByPath(final String path);
  Future<void> saveRecord(final CloudKitRecord record);
  Future<void> deleteRecord(final String recordName);
  Future<List<CloudKitRecord>> queryByPathPrefix(final String pathPrefix);
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken});
  Future<void> dispose();
}
