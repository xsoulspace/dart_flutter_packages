import 'cloudkit_apple_api.g.dart';

/// Typed client abstraction for Apple CloudKit bridge RPC.
abstract interface class CloudKitAppleApiClient {
  Future<void> initialize(final CloudKitAppleConfigData config);

  Future<CloudKitAppleRecordData?> fetchRecordByPath(final String path);

  Future<void> saveRecord(final CloudKitAppleRecordData record);

  Future<void> deleteRecord(final String recordName);

  Future<List<CloudKitAppleRecordData>> queryByPathPrefix(
    final String pathPrefix,
  );

  Future<CloudKitAppleDeltaData> fetchChanges(final String? serverChangeToken);

  Future<void> dispose();
}

/// Pigeon-backed implementation of [CloudKitAppleApiClient].
class PigeonCloudKitAppleApiClient implements CloudKitAppleApiClient {
  PigeonCloudKitAppleApiClient({final CloudKitAppleHostApi? api})
    : _api = api ?? CloudKitAppleHostApi();

  final CloudKitAppleHostApi _api;

  @override
  Future<void> initialize(final CloudKitAppleConfigData config) =>
      _api.initialize(config);

  @override
  Future<CloudKitAppleRecordData?> fetchRecordByPath(final String path) =>
      _api.fetchRecordByPath(path);

  @override
  Future<void> saveRecord(final CloudKitAppleRecordData record) =>
      _api.saveRecord(record);

  @override
  Future<void> deleteRecord(final String recordName) =>
      _api.deleteRecord(recordName);

  @override
  Future<List<CloudKitAppleRecordData>> queryByPathPrefix(
    final String pathPrefix,
  ) => _api.queryByPathPrefix(pathPrefix);

  @override
  Future<CloudKitAppleDeltaData> fetchChanges(
    final String? serverChangeToken,
  ) => _api.fetchChanges(serverChangeToken);

  @override
  Future<void> dispose() => _api.dispose();
}
