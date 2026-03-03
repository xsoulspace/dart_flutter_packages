import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_cloudkit_apple/universal_storage_cloudkit_apple.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

void main() {
  test('bridge delegates typed calls through api client', () async {
    final fake = _FakeAppleApiClient();
    final bridge = MethodChannelCloudKitAppleBridge(apiClient: fake);

    await bridge.initialize(
      const CloudKitBridgeConfig(
        containerId: 'iCloud.com.example.app',
        environment: CloudKitEnvironment.development,
        databaseScope: CloudKitDatabaseScope.privateDb,
        zoneName: 'UniversalStorageZone',
        recordType: 'USFile',
        maxInlineBytes: 262144,
      ),
    );

    await bridge.saveRecord(
      CloudKitRecord(
        recordName: 'abc',
        path: 'a.txt',
        content: 'hello',
        checksum: 'sum',
        size: 5,
        updatedAt: DateTime.utc(2026, 3, 3),
      ),
    );

    final fetched = await bridge.fetchRecordByPath('a.txt');
    final listed = await bridge.queryByPathPrefix('');
    final delta = await bridge.fetchChanges(serverChangeToken: 'prev');

    expect(fake.initialized, isTrue);
    expect(fetched?.path, equals('a.txt'));
    expect(listed, hasLength(1));
    expect(delta.nextServerChangeToken, equals('next-token'));
  });
}

class _FakeAppleApiClient implements CloudKitAppleApiClient {
  bool initialized = false;
  final Map<String, CloudKitAppleRecordData> recordsByPath =
      <String, CloudKitAppleRecordData>{};

  @override
  Future<void> initialize(final CloudKitAppleConfigData config) async {
    initialized = true;
  }

  @override
  Future<CloudKitAppleRecordData?> fetchRecordByPath(final String path) async =>
      recordsByPath[path];

  @override
  Future<void> saveRecord(final CloudKitAppleRecordData record) async {
    recordsByPath[record.path] = record;
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    recordsByPath.removeWhere((final _, final record) {
      return record.recordName == recordName;
    });
  }

  @override
  Future<List<CloudKitAppleRecordData>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    return recordsByPath.values.toList(growable: false);
  }

  @override
  Future<CloudKitAppleDeltaData> fetchChanges(
    final String? serverChangeToken,
  ) async {
    return CloudKitAppleDeltaData(nextServerChangeToken: 'next-token');
  }

  @override
  Future<void> dispose() async {}
}
