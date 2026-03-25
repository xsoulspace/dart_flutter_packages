import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

import 'cloudkit_web_client.dart';
import 'cloudkit_web_client_factory.dart';

/// Registers the web bridge instance as active CloudKit bridge.
void registerCloudKitWebBridge({final CloudKitWebClient? client}) {
  CloudKitBridgePlatform.instance = CloudKitWebBridge(client: client);
}

/// CloudKit bridge implementation for web runtimes.
class CloudKitWebBridge implements CloudKitBridge {
  CloudKitWebBridge({final CloudKitWebClient? client})
    : _client = client ?? createDefaultCloudKitWebClient();

  final CloudKitWebClient _client;

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    if (config.webApiToken == null || config.webApiToken!.trim().isEmpty) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.authentication,
        message:
            'webApiToken is required for CloudKit web bridge initialization.',
        details: <String, Object?>{'action': 'provide_web_api_token'},
      );
    }

    await _client.initialize(config);
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) =>
      _client.fetchRecordByPath(path);

  @override
  Future<void> saveRecord(final CloudKitRecord record) =>
      _client.saveRecord(record);

  @override
  Future<void> deleteRecord(final String recordName) =>
      _client.deleteRecord(recordName);

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(final String pathPrefix) =>
      _client.queryByPathPrefix(pathPrefix);

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) =>
      _client.fetchChanges(serverChangeToken: serverChangeToken);

  @override
  Future<void> dispose() => _client.dispose();
}
