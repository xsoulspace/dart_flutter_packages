@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';
import 'package:universal_storage_cloudkit_web/universal_storage_cloudkit_web.dart';

void main() {
  late JSAny? originalCloudKit;

  setUp(() {
    originalCloudKit = globalContext['CloudKit'];
  });

  tearDown(() {
    globalContext['CloudKit'] = originalCloudKit;
  });

  test(
    'native CloudKit JS surface supports CRUD and query operations',
    () async {
      final stub = _NativeCloudKitStub();
      _installNativeCloudKitStub(stub);

      final bridge = CloudKitWebBridge();
      await bridge.initialize(
        const CloudKitBridgeConfig(
          containerId: 'iCloud.com.example.app',
          environment: CloudKitEnvironment.development,
          databaseScope: CloudKitDatabaseScope.privateDb,
          zoneName: 'UniversalStorageZone',
          recordType: 'USFile',
          maxInlineBytes: 262144,
          webApiToken: 'web-token',
        ),
      );

      expect(stub.lastConfigurePayload, isNotNull);

      final record = CloudKitRecord(
        recordName: 'record-1',
        path: 'docs/file.json',
        content: '{"hello":"world"}',
        checksum: 'sum-1',
        size: 17,
        updatedAt: DateTime.utc(2026, 3, 3, 12),
      );
      await bridge.saveRecord(record);

      final fetched = await bridge.fetchRecordByPath(record.path);
      expect(fetched, isNotNull);
      expect(fetched!.content, equals(record.content));

      final listed = await bridge.queryByPathPrefix('docs');
      expect(listed.map((final item) => item.path), contains(record.path));

      await bridge.deleteRecord(record.recordName);
      expect(await bridge.fetchRecordByPath(record.path), isNull);
    },
  );

  test(
    'native fetchChangedRecords maps deleted record names to deleted paths',
    () async {
      final stub = _NativeCloudKitStub();
      _installNativeCloudKitStub(stub);

      final bridge = CloudKitWebBridge();
      await bridge.initialize(
        const CloudKitBridgeConfig(
          containerId: 'iCloud.com.example.app',
          environment: CloudKitEnvironment.development,
          databaseScope: CloudKitDatabaseScope.privateDb,
          zoneName: 'UniversalStorageZone',
          recordType: 'USFile',
          maxInlineBytes: 262144,
          webApiToken: 'web-token',
        ),
      );

      final record = CloudKitRecord(
        recordName: 'record-2',
        path: 'projects/p1.json',
        content: '{"id":"p1"}',
        checksum: 'sum-2',
        size: 11,
        updatedAt: DateTime.utc(2026, 3, 3, 13),
      );
      await bridge.saveRecord(record);

      stub.changedRecords = <Map<String, Object?>>[
        _nativeRecord(
          recordName: record.recordName,
          path: record.path,
          content: '{"id":"p1","v":2}',
          checksum: 'sum-2b',
          size: 17,
          updatedAtMillis: DateTime.utc(2026, 3, 3, 14).millisecondsSinceEpoch,
          changeTag: 'server-v2',
        ),
      ];
      stub.deletedRecordNames = <Object?>[record.recordName];

      final delta = await bridge.fetchChanges(serverChangeToken: 'sync-1');

      expect(delta.nextServerChangeToken, equals('next-sync-token'));
      expect(delta.updatedRecords, hasLength(1));
      expect(delta.updatedRecords.first.content, equals('{"id":"p1","v":2}'));
      expect(delta.deletedPaths, contains(record.path));
      expect(stub.lastSyncToken, equals('sync-1'));
    },
  );
}

class _NativeCloudKitStub {
  Map<String, Object?>? lastConfigurePayload;
  final Map<String, Map<String, Object?>> recordsByPath =
      <String, Map<String, Object?>>{};
  final Map<String, String> pathByRecordName = <String, String>{};
  List<Map<String, Object?>> changedRecords = <Map<String, Object?>>[];
  List<Object?> deletedRecordNames = <Object?>[];
  String? lastSyncToken;
}

void _installNativeCloudKitStub(final _NativeCloudKitStub stub) {
  final database = JSObject();
  database['performQuery'] = ((final JSAny? requestRaw) {
    final request = _asMap(requestRaw);
    final query = _asMap(request['query']);
    final filters = query['filterBy'];
    final records = stub.recordsByPath.values.toList(growable: false);

    if (filters is List && filters.isNotEmpty) {
      final filter = _asMap(filters.first);
      final comparator = (filter['comparator'] ?? '').toString();
      final fieldName = (filter['fieldName'] ?? '').toString();
      final fieldValue =
          _asMap(filter['fieldValue'])['value']?.toString() ?? '';
      if (fieldName == 'path') {
        final matched = records
            .where((final record) {
              final path = _fieldString(record['fields'], 'path');
              if (comparator == 'EQUALS' || comparator == 'EQUAL') {
                return path == fieldValue;
              }
              return path.startsWith(fieldValue);
            })
            .toList(growable: false);
        return <String, Object?>{'records': matched}.jsify();
      }
    }

    return <String, Object?>{'records': records}.jsify();
  }).toJS;

  database['saveRecords'] = ((final JSAny? requestRaw) {
    final request = _asMap(requestRaw);
    final records = request['records'];
    if (records is List) {
      for (final recordRaw in records) {
        final record = _asMap(recordRaw);
        final fields = _asMap(record['fields']);
        final path = _fieldString(fields, 'path');
        final recordName = (record['recordName'] ?? '').toString();
        if (path.isEmpty || recordName.isEmpty) {
          continue;
        }

        final normalized = _nativeRecord(
          recordName: recordName,
          path: path,
          content: _fieldString(fields, 'content'),
          checksum: _fieldString(fields, 'checksum'),
          size: _fieldInt(fields, 'size'),
          updatedAtMillis: _fieldInt(fields, 'updatedAt'),
          changeTag: record['recordChangeTag']?.toString(),
        );
        stub.recordsByPath[path] = normalized;
        stub.pathByRecordName[recordName] = path;
      }
    }
    return <String, Object?>{
      'records': stub.recordsByPath.values.toList(),
    }.jsify();
  }).toJS;

  database['deleteRecords'] = ((final JSAny? requestRaw) {
    final request = _asMap(requestRaw);
    final names = <String>[];
    final rawNames = request['recordNames'];
    if (rawNames is List) {
      names.addAll(rawNames.map((final item) => item.toString()));
    }
    final rawRecords = request['records'];
    if (rawRecords is List) {
      for (final item in rawRecords) {
        final name = _asMap(item)['recordName']?.toString();
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
    }

    for (final name in names) {
      final path = stub.pathByRecordName.remove(name);
      if (path != null) {
        stub.recordsByPath.remove(path);
      }
    }
    return null;
  }).toJS;

  database['fetchChangedRecords'] = ((final JSAny? requestRaw) {
    final request = _asMap(requestRaw);
    stub.lastSyncToken = request['syncToken']?.toString();
    final changed = stub.changedRecords.isEmpty
        ? stub.recordsByPath.values.toList(growable: false)
        : stub.changedRecords;
    return <String, Object?>{
      'records': changed,
      'deletedRecordNames': stub.deletedRecordNames,
      'syncToken': 'next-sync-token',
    }.jsify();
  }).toJS;

  final container = JSObject();
  container['privateCloudDatabase'] = database;
  container['setUpAuth'] = (() => <String, Object?>{'isAuthenticated': true}.jsify()).toJS;

  final cloudKit = JSObject();
  cloudKit['configure'] = ((final JSAny? payloadRaw) {
    stub.lastConfigurePayload = _asMap(payloadRaw);
    return null;
  }).toJS;
  cloudKit['getDefaultContainer'] = (() => container).toJS;

  globalContext['CloudKit'] = cloudKit;
}

Map<String, Object?> _asMap(final Object? value) {
  if (value == null) {
    return <String, Object?>{};
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  try {
    final dartified = (value as JSAny).dartify();
    if (dartified is Map) {
      return Map<String, Object?>.from(dartified);
    }
  } catch (_) {
    // Best-effort conversion helper for JS interop test payloads.
  }
  return <String, Object?>{};
}

String _fieldString(final Object? fieldsRaw, final String key) {
  final fields = _asMap(fieldsRaw);
  final raw = fields[key];
  if (raw is Map) {
    final mapped = Map<String, Object?>.from(raw);
    return mapped['value']?.toString() ?? '';
  }
  return raw?.toString() ?? '';
}

int _fieldInt(final Object? fieldsRaw, final String key) {
  final text = _fieldString(fieldsRaw, key);
  return int.tryParse(text) ?? 0;
}

Map<String, Object?> _nativeRecord({
  required final String recordName,
  required final String path,
  required final String content,
  required final String checksum,
  required final int size,
  required final int updatedAtMillis,
  final String? changeTag,
}) => <String, Object?>{
  'recordName': recordName,
  'recordChangeTag': ?changeTag,
  'fields': <String, Object?>{
    'path': <String, Object?>{'value': path},
    'content': <String, Object?>{'value': content},
    'checksum': <String, Object?>{'value': checksum},
    'size': <String, Object?>{'value': size},
    'updatedAt': <String, Object?>{'value': updatedAtMillis},
  },
};
