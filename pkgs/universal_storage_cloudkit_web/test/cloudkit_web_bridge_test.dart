import 'package:test/test.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';
import 'package:universal_storage_cloudkit_web/universal_storage_cloudkit_web.dart';

void main() {
  test('CloudKitWebBridge requires webApiToken on initialize', () async {
    final bridge = CloudKitWebBridge(client: _FakeClient());

    await expectLater(
      () => bridge.initialize(
        const CloudKitBridgeConfig(
          containerId: 'iCloud.com.example.app',
          environment: CloudKitEnvironment.development,
          databaseScope: CloudKitDatabaseScope.privateDb,
          zoneName: 'UniversalStorageZone',
          recordType: 'USFile',
          maxInlineBytes: 262144,
        ),
      ),
      throwsA(isA<CloudKitBridgeException>()),
    );
  });

  test('CloudKitWebBridge delegates to client operations', () async {
    final client = _FakeClient();
    final bridge = CloudKitWebBridge(client: client);

    await bridge.initialize(
      const CloudKitBridgeConfig(
        containerId: 'iCloud.com.example.app',
        environment: CloudKitEnvironment.development,
        databaseScope: CloudKitDatabaseScope.privateDb,
        zoneName: 'UniversalStorageZone',
        recordType: 'USFile',
        maxInlineBytes: 262144,
        webApiToken: 'token',
      ),
    );

    await bridge.saveRecord(
      CloudKitRecord(
        recordName: 'a',
        path: 'a.txt',
        content: 'hello',
        checksum: 'sum',
        size: 5,
        updatedAt: DateTime.utc(2026, 3, 3),
      ),
    );

    expect((await bridge.fetchRecordByPath('a.txt'))?.content, equals('hello'));
    expect(await bridge.queryByPathPrefix(''), hasLength(1));
    expect(
      (await bridge.fetchChanges()).nextServerChangeToken,
      equals('next-token'),
    );
  });
}

class _FakeClient implements CloudKitWebClient {
  final Map<String, CloudKitRecord> _records = <String, CloudKitRecord>{};

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {}

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async =>
      _records[path];

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    _records[record.path] = record;
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    _records.removeWhere(
      (final _, final value) => value.recordName == recordName,
    );
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async => _records.values.toList(growable: false);

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async =>
      const CloudKitDelta(nextServerChangeToken: 'next-token');

  @override
  Future<void> dispose() async {}
}
