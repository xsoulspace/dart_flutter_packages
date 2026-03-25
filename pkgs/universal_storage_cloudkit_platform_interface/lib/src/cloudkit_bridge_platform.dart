import 'models.dart';

/// Contract implemented by platform-specific CloudKit bridges.
abstract interface class CloudKitBridge {
  Future<void> initialize(final CloudKitBridgeConfig config);

  Future<CloudKitRecord?> fetchRecordByPath(final String path);

  Future<void> saveRecord(final CloudKitRecord record);

  Future<void> deleteRecord(final String recordName);

  Future<List<CloudKitRecord>> queryByPathPrefix(final String pathPrefix);

  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken});

  Future<void> dispose();
}

/// Global bridge holder used by universal_storage_cloudkit provider.
abstract final class CloudKitBridgePlatform {
  CloudKitBridgePlatform._();

  static CloudKitBridge instance = const UnsupportedCloudKitBridge();
}

class UnsupportedCloudKitBridge implements CloudKitBridge {
  const UnsupportedCloudKitBridge();

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async {
    throw const CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unsupported,
      message: 'CloudKit bridge is not registered for this platform.',
    );
  }

  @override
  Future<void> dispose() async {}
}
