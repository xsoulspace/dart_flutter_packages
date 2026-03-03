// ignore_for_file: avoid_dynamic_calls

import 'dart:js_util' as js_util;

import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

import 'cloudkit_web_client.dart';
import 'raw/cloudkit_raw.dart';

CloudKitWebClient createDefaultCloudKitWebClient() =>
    const CloudKitJsInteropClient();

/// JS-interop implementation for CloudKit web bridge.
///
/// This wrapper expects `window.CloudKit` to expose adapter methods:
/// `initialize`, `fetchRecordByPath`, `saveRecord`, `deleteRecord`,
/// `queryByPathPrefix`, and `fetchChanges`.
class CloudKitJsInteropClient implements CloudKitWebClient {
  const CloudKitJsInteropClient();

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    await _invokeVoid('initialize', config.toMap());
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async {
    final response = await _invoke('fetchRecordByPath', <String, Object?>{
      'path': path,
    });

    if (response == null) {
      return null;
    }

    final map = Map<String, Object?>.from(response as Map);
    return CloudKitRecord.fromMap(map);
  }

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    await _invokeVoid('saveRecord', record.toMap());
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    await _invokeVoid('deleteRecord', <String, Object?>{
      'recordName': recordName,
    });
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    final response = await _invoke('queryByPathPrefix', <String, Object?>{
      'pathPrefix': pathPrefix,
    });

    if (response is! List) {
      return const <CloudKitRecord>[];
    }

    return response
        .whereType<Map>()
        .map(
          (final item) =>
              CloudKitRecord.fromMap(Map<String, Object?>.from(item)),
        )
        .toList(growable: false);
  }

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async {
    final response = await _invoke('fetchChanges', <String, Object?>{
      if (serverChangeToken != null) 'serverChangeToken': serverChangeToken,
    });

    if (response is! Map) {
      return CloudKitDelta.empty();
    }

    final map = Map<String, Object?>.from(response);
    final updatedRaw = map['updatedRecords'];
    final deletedRaw = map['deletedPaths'];
    final updated = (updatedRaw is List ? updatedRaw : const <Object?>[])
        .whereType<Map>()
        .map(
          (final item) =>
              CloudKitRecord.fromMap(Map<String, Object?>.from(item)),
        )
        .toList(growable: false);
    final deleted = (deletedRaw is List ? deletedRaw : const <Object?>[])
        .map((final item) => item?.toString() ?? '')
        .where((final item) => item.isNotEmpty)
        .toList(growable: false);

    return CloudKitDelta(
      updatedRecords: updated,
      deletedPaths: deleted,
      nextServerChangeToken: map['nextServerChangeToken']?.toString(),
    );
  }

  @override
  Future<void> dispose() async {
    await _invokeVoid('dispose', const <String, Object?>{});
  }

  Future<void> _invokeVoid(final String method, [final Object? args]) async {
    await _invoke(method, args);
  }

  Future<Object?> _invoke(final String method, [final Object? args]) async {
    if (!hasCloudKitGlobal) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit JS global is missing. Load CloudKit JS before init.',
        details: const <String, Object?>{'action': 'load_cloudkit_js'},
      );
    }

    final global = js_util.getProperty<Object?>(js_util.globalThis, 'CloudKit');
    if (global == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'window.CloudKit is undefined.',
      );
    }

    final result = args == null
        ? js_util.callMethod<Object?>(global, method, const <Object?>[])
        : js_util.callMethod<Object?>(global, method, <Object?>[
            js_util.jsify(args),
          ]);

    if (result is Future<Object?>) {
      return result;
    }

    if (result != null && js_util.hasProperty(result, 'then')) {
      return js_util.promiseToFuture<Object?>(result);
    }

    return result;
  }
}
