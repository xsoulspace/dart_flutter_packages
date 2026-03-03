// ignore_for_file: avoid_dynamic_calls

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

import 'cloudkit_web_client.dart';
import 'raw/cloudkit_raw.dart';

CloudKitWebClient createDefaultCloudKitWebClient() => CloudKitJsInteropClient();

/// JS-interop implementation for CloudKit web bridge.
///
/// Preferred mode uses the native CloudKit JS object model:
/// - `CloudKit.configure(...)`
/// - `CloudKit.getDefaultContainer()`
/// - `container.privateCloudDatabase.*`
///
/// Compatibility mode supports an adapter-style global surface with methods:
/// `initialize`, `fetchRecordByPath`, `saveRecord`, `deleteRecord`,
/// `queryByPathPrefix`, and `fetchChanges`.
class CloudKitJsInteropClient implements CloudKitWebClient {
  CloudKitJsInteropClient();

  final Map<String, String> _pathByRecordName = <String, String>{};

  _CloudKitClientMode _mode = _CloudKitClientMode.uninitialized;
  CloudKitBridgeConfig? _config;
  JSObject? _cloudKit;
  JSObject? _database;

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    final cloudKit = _resolveCloudKitGlobal();
    _cloudKit = cloudKit;
    _config = config;
    _database = null;
    _pathByRecordName.clear();

    if (_hasAdapterSurface(cloudKit)) {
      _mode = _CloudKitClientMode.adapter;
      await _invokeAdapter('initialize', config.toMap());
      return;
    }

    _mode = _CloudKitClientMode.native;
    await _initializeNative(config);
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async {
    _ensureInitialized();
    if (_mode == _CloudKitClientMode.adapter) {
      final response = await _invokeAdapter(
        'fetchRecordByPath',
        <String, Object?>{'path': path},
      );
      if (response == null) {
        return null;
      }
      return _toCloudKitRecord(Map<String, Object?>.from(response as Map));
    }

    final records = await _queryNative(path: path, exactMatch: true, limit: 1);
    if (records.isEmpty) {
      return null;
    }
    return _toCloudKitRecord(records.first);
  }

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    _ensureInitialized();
    if (_mode == _CloudKitClientMode.adapter) {
      await _invokeAdapter('saveRecord', record.toMap());
      return;
    }

    final payload = <String, Object?>{
      'zoneID': _zoneIdPayload(),
      'records': <Object?>[_toNativeRecordPayload(record)],
    };
    await _invokeNativeDatabase('saveRecords', payload);
    _pathByRecordName[record.recordName] = record.path;
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    _ensureInitialized();
    if (_mode == _CloudKitClientMode.adapter) {
      await _invokeAdapter('deleteRecord', <String, Object?>{
        'recordName': recordName,
      });
      _pathByRecordName.remove(recordName);
      return;
    }

    final payloadByName = <String, Object?>{
      'zoneID': _zoneIdPayload(),
      'recordNames': <String>[recordName],
    };
    try {
      await _invokeNativeDatabase('deleteRecords', payloadByName);
    } on CloudKitBridgeException {
      final payloadByRecord = <String, Object?>{
        'zoneID': _zoneIdPayload(),
        'records': <Object?>[
          <String, Object?>{
            'recordName': recordName,
            'zoneID': _zoneIdPayload(),
          },
        ],
      };
      await _invokeNativeDatabase('deleteRecords', payloadByRecord);
    }
    _pathByRecordName.remove(recordName);
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async {
    _ensureInitialized();
    if (_mode == _CloudKitClientMode.adapter) {
      final response = await _invokeAdapter(
        'queryByPathPrefix',
        <String, Object?>{'pathPrefix': pathPrefix},
      );
      if (response is! List) {
        return const <CloudKitRecord>[];
      }
      return response
          .whereType<Map>()
          .map(
            (final item) => _toCloudKitRecord(Map<String, Object?>.from(item)),
          )
          .toList(growable: false);
    }

    final records = await _queryNative(path: pathPrefix, exactMatch: false);
    final output = records.map(_toCloudKitRecord).toList(growable: false)
      ..sort((final a, final b) => a.path.compareTo(b.path));
    return output;
  }

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async {
    _ensureInitialized();
    if (_mode == _CloudKitClientMode.adapter) {
      final response = await _invokeAdapter('fetchChanges', <String, Object?>{
        if (serverChangeToken != null) 'serverChangeToken': serverChangeToken,
      });
      if (response is! Map) {
        return CloudKitDelta(nextServerChangeToken: serverChangeToken);
      }
      return _toCloudKitDelta(
        Map<String, Object?>.from(response),
        fallbackToken: serverChangeToken,
      );
    }

    if (_hasDatabaseMethod('fetchChangedRecords')) {
      final response =
          await _invokeNativeDatabase('fetchChangedRecords', <String, Object?>{
            'zoneID': _zoneIdPayload(),
            if (serverChangeToken != null) 'syncToken': serverChangeToken,
          });
      return _toCloudKitDelta(response, fallbackToken: serverChangeToken);
    }

    if (_hasDatabaseMethod('fetchChanges')) {
      final response = await _invokeNativeDatabase(
        'fetchChanges',
        <String, Object?>{
          if (serverChangeToken != null) 'serverChangeToken': serverChangeToken,
        },
      );
      return _toCloudKitDelta(response, fallbackToken: serverChangeToken);
    }

    return CloudKitDelta(nextServerChangeToken: serverChangeToken);
  }

  @override
  Future<void> dispose() async {
    if (_mode == _CloudKitClientMode.adapter && _cloudKit != null) {
      if (_hasMethod(_cloudKit!, 'dispose')) {
        try {
          await _invokeAdapter('dispose', const <String, Object?>{});
        } catch (_) {
          // Best-effort cleanup for adapter implementations.
        }
      }
    }
    _mode = _CloudKitClientMode.uninitialized;
    _config = null;
    _cloudKit = null;
    _database = null;
    _pathByRecordName.clear();
  }

  Future<void> _initializeNative(final CloudKitBridgeConfig config) async {
    final cloudKit = _cloudKit;
    if (cloudKit == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit JS global is unavailable.',
      );
    }

    if (!_hasMethod(cloudKit, 'configure')) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit.configure(...) is unavailable on window.CloudKit.',
        details: const <String, Object?>{'action': 'load_full_cloudkit_js_sdk'},
      );
    }

    await _invokeTarget(
      cloudKit,
      'configure',
      args: _nativeConfigurePayload(config),
    );

    JSObject? container;
    if (_hasMethod(cloudKit, 'getDefaultContainer')) {
      container =
          await _invokeTarget(
                cloudKit,
                'getDefaultContainer',
                dartifyResult: false,
              )
              as JSObject?;
    } else if (_hasMethod(cloudKit, 'getContainer')) {
      container =
          await _invokeTarget(
                cloudKit,
                'getContainer',
                args: config.containerId,
                dartifyResult: false,
              )
              as JSObject?;
    }

    if (container == null) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message:
            'CloudKit container APIs are unavailable (expected getDefaultContainer/getContainer).',
        details: const <String, Object?>{'action': 'load_full_cloudkit_js_sdk'},
      );
    }

    if (_hasMethod(container, 'setUpAuth')) {
      final authResult = await _invokeTarget(container, 'setUpAuth');
      _throwIfAuthSetupFailed(authResult);
    }

    JSObject? database;
    if (container.has('privateCloudDatabase')) {
      final databaseValue = container['privateCloudDatabase'];
      if (databaseValue != null) {
        database = databaseValue as JSObject?;
      }
    } else if (_hasMethod(container, 'getDatabaseWithDatabaseScope')) {
      database =
          await _invokeTarget(
                container,
                'getDatabaseWithDatabaseScope',
                args: 'private',
                dartifyResult: false,
              )
              as JSObject?;
    }

    if (database == null) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit privateCloudDatabase is unavailable.',
        details: const <String, Object?>{
          'action': 'verify_cloudkit_container_capabilities',
        },
      );
    }

    _database = database;
  }

  Future<List<Map<String, Object?>>> _queryNative({
    required final String path,
    required final bool exactMatch,
    final int? limit,
  }) async {
    final comparators = exactMatch
        ? const <String>['EQUALS', 'EQUAL']
        : const <String>['BEGINS_WITH', 'BEGINSWITH', 'STARTS_WITH'];

    CloudKitBridgeException? lastError;
    for (final comparator in comparators) {
      try {
        final filterBy = <Map<String, Object?>>[
          <String, Object?>{
            'fieldName': 'path',
            'comparator': comparator,
            'fieldValue': <String, Object?>{'value': path},
          },
        ];
        final payload = <String, Object?>{
          'zoneID': _zoneIdPayload(),
          'query': <String, Object?>{
            'recordType': _config!.recordType,
            'filterBy': filterBy,
          },
          if (limit != null) 'resultsLimit': limit,
        };
        final response = await _invokeNativeDatabase('performQuery', payload);
        return _extractRecordMaps(response);
      } on CloudKitBridgeException catch (error) {
        lastError = error;
      }
    }

    if (path.isEmpty) {
      final payload = <String, Object?>{
        'zoneID': _zoneIdPayload(),
        'query': <String, Object?>{'recordType': _config!.recordType},
      };
      final response = await _invokeNativeDatabase('performQuery', payload);
      return _extractRecordMaps(response);
    }

    if (lastError != null) {
      throw lastError;
    }
    return const <Map<String, Object?>>[];
  }

  List<Map<String, Object?>> _extractRecordMaps(final Object? response) {
    if (response is List) {
      return response
          .whereType<Map>()
          .map((final item) => Map<String, Object?>.from(item))
          .toList(growable: false);
    }
    if (response is Map) {
      final map = Map<String, Object?>.from(response);
      final recordsValue =
          map['records'] ?? map['results'] ?? map['updatedRecords'];
      if (recordsValue is List) {
        return recordsValue
            .whereType<Map>()
            .map((final item) => Map<String, Object?>.from(item))
            .toList(growable: false);
      }
    }
    return const <Map<String, Object?>>[];
  }

  CloudKitDelta _toCloudKitDelta(
    final Object? response, {
    required final String? fallbackToken,
  }) {
    if (response is! Map) {
      return CloudKitDelta(nextServerChangeToken: fallbackToken);
    }

    final map = Map<String, Object?>.from(response);
    final updatedRaw =
        map['updatedRecords'] ?? map['changedRecords'] ?? map['records'];
    final deletedRaw =
        map['deletedPaths'] ?? map['deletedRecordNames'] ?? map['deletions'];

    final updated = <CloudKitRecord>[];
    if (updatedRaw is List) {
      for (final item in updatedRaw.whereType<Map>()) {
        updated.add(_toCloudKitRecord(Map<String, Object?>.from(item)));
      }
    }

    final deleted = <String>[];
    if (deletedRaw is List) {
      for (final item in deletedRaw) {
        final path = _pathFromDeletion(item);
        if (path != null && path.isNotEmpty) {
          deleted.add(path);
        }
      }
    }

    final nextToken =
        _stringOrNull(map['nextServerChangeToken']) ??
        _stringOrNull(map['serverChangeToken']) ??
        _stringOrNull(map['syncToken']) ??
        fallbackToken;

    return CloudKitDelta(
      updatedRecords: updated,
      deletedPaths: deleted,
      nextServerChangeToken: nextToken,
    );
  }

  String? _pathFromDeletion(final Object? entry) {
    if (entry is String) {
      if (entry.contains('/')) {
        return entry;
      }
      return _pathByRecordName[entry];
    }
    if (entry is Map) {
      final map = Map<String, Object?>.from(entry);
      final path = _stringOrNull(map['path']);
      if (path != null && path.isNotEmpty) {
        return path;
      }

      final recordName =
          _stringOrNull(map['recordName']) ??
          _stringOrNull((map['recordID'] as Map?)?['recordName']);
      if (recordName != null) {
        return _pathByRecordName[recordName];
      }
    }
    return null;
  }

  CloudKitRecord _toCloudKitRecord(final Map<String, Object?> recordMap) {
    final fields = _mapOrEmpty(recordMap['fields']);
    final recordName =
        _stringOrNull(recordMap['recordName']) ??
        _stringOrNull(_mapOrEmpty(recordMap['recordID'])['recordName']) ??
        '';
    final path =
        _stringOrNull(_fieldValue(fields['path'])) ??
        _stringOrNull(recordMap['path']) ??
        '';
    final content =
        _stringOrNull(_fieldValue(fields['content'])) ??
        _stringOrNull(recordMap['content']) ??
        '';
    final checksum =
        _stringOrNull(_fieldValue(fields['checksum'])) ??
        _stringOrNull(recordMap['checksum']) ??
        '';
    final size = _intOrZero(_fieldValue(fields['size']) ?? recordMap['size']);
    final updatedAt = _parseDate(
      _fieldValue(fields['updatedAt']) ??
          recordMap['updatedAt'] ??
          recordMap['modifiedTimestamp'],
    );
    final changeTag =
        _stringOrNull(recordMap['recordChangeTag']) ??
        _stringOrNull(recordMap['changeTag']);

    if (recordName.isNotEmpty && path.isNotEmpty) {
      _pathByRecordName[recordName] = path;
    }

    return CloudKitRecord(
      recordName: recordName,
      path: path,
      content: content,
      checksum: checksum,
      size: size,
      updatedAt: updatedAt,
      changeTag: changeTag,
    );
  }

  Map<String, Object?> _toNativeRecordPayload(final CloudKitRecord record) =>
      <String, Object?>{
        'recordName': record.recordName,
        'recordType': _config!.recordType,
        'zoneID': _zoneIdPayload(),
        if (record.changeTag != null && record.changeTag!.isNotEmpty)
          'recordChangeTag': record.changeTag,
        'fields': <String, Object?>{
          'path': <String, Object?>{'value': record.path},
          'content': <String, Object?>{'value': record.content},
          'checksum': <String, Object?>{'value': record.checksum},
          'size': <String, Object?>{'value': record.size},
          'updatedAt': <String, Object?>{
            'value': record.updatedAt.toUtc().millisecondsSinceEpoch,
          },
        },
      };

  Map<String, Object?> _nativeConfigurePayload(
    final CloudKitBridgeConfig config,
  ) {
    final environment = config.environment.name;
    return <String, Object?>{
      'containerIdentifier': config.containerId,
      'environment': environment,
      'containers': <Map<String, Object?>>[
        <String, Object?>{
          'containerIdentifier': config.containerId,
          'environment': environment,
          'apiTokenAuth': <String, Object?>{
            'apiToken': config.webApiToken,
            'persist': true,
          },
        },
      ],
    };
  }

  Map<String, Object?> _zoneIdPayload() => <String, Object?>{
    'zoneName': _config!.zoneName,
  };

  void _throwIfAuthSetupFailed(final Object? response) {
    if (response is! Map) {
      return;
    }

    final map = Map<String, Object?>.from(response);
    final hasRedirect = _stringOrNull(map['redirectURL']) != null;
    final isAuthenticated = map['isAuthenticated'];
    if (hasRedirect || isAuthenticated == false) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.authentication,
        message: 'CloudKit web authentication flow requires user action.',
        details: <String, Object?>{
          'action': 'complete_cloudkit_web_authentication',
          if (map['redirectURL'] != null) 'redirectURL': map['redirectURL'],
        },
      );
    }
  }

  void _ensureInitialized() {
    if (_mode == _CloudKitClientMode.uninitialized || _config == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.authentication,
        message: 'CloudKit web client is not initialized.',
      );
    }
  }

  bool _hasAdapterSurface(final JSObject cloudKit) =>
      _hasMethod(cloudKit, 'initialize') &&
      _hasMethod(cloudKit, 'fetchRecordByPath') &&
      _hasMethod(cloudKit, 'saveRecord') &&
      _hasMethod(cloudKit, 'deleteRecord') &&
      _hasMethod(cloudKit, 'queryByPathPrefix') &&
      _hasMethod(cloudKit, 'fetchChanges');

  bool _hasDatabaseMethod(final String method) =>
      _database != null && _hasMethod(_database!, method);

  bool _hasMethod(final JSObject target, final String method) =>
      target.has(method);

  JSObject _resolveCloudKitGlobal() {
    if (!hasCloudKitGlobal) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit JS global is missing. Load CloudKit JS before init.',
        details: const <String, Object?>{'action': 'load_cloudkit_js'},
      );
    }
    final global = globalContext['CloudKit'];
    if (global == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'window.CloudKit is undefined.',
      );
    }
    return global as JSObject;
  }

  Future<Object?> _invokeAdapter(
    final String method, [
    final Object? args,
  ]) async {
    final cloudKit = _cloudKit;
    if (cloudKit == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit JS global is unavailable.',
      );
    }
    return _invokeTarget(cloudKit, method, args: args);
  }

  Future<Object?> _invokeNativeDatabase(
    final String method, [
    final Object? args,
  ]) async {
    final database = _database;
    if (database == null) {
      throw const CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit privateCloudDatabase is not initialized.',
      );
    }
    if (!_hasMethod(database, method)) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message:
            'CloudKit privateCloudDatabase method "$method" is unavailable.',
        details: <String, Object?>{
          'action': 'load_full_cloudkit_js_sdk',
          'method': method,
        },
      );
    }
    return _invokeTarget(database, method, args: args, dartifyResult: true);
  }

  Future<Object?> _invokeTarget(
    final JSObject target,
    final String method, {
    final Object? args,
    final bool dartifyResult = true,
  }) async {
    if (!_hasMethod(target, method)) {
      throw CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.unsupported,
        message: 'CloudKit JS method "$method" is unavailable.',
        details: <String, Object?>{
          'action': 'verify_cloudkit_js_surface',
          'method': method,
        },
      );
    }

    final result = _callJsMethod(target, method, args);
    if (_isThenable(result)) {
      try {
        final value = await (result as JSPromise<JSAny?>).toDart;
        return dartifyResult ? _normalizeResult(value) : value;
      } catch (error) {
        throw _mapWebError(method: method, error: error);
      }
    }
    return dartifyResult ? _normalizeResult(result) : result;
  }

  JSAny? _callJsMethod(
    final JSObject target,
    final String method,
    final Object? args,
  ) {
    try {
      return args == null
          ? target.callMethodVarArgs<JSAny?>(method.toJS)
          : target.callMethodVarArgs<JSAny?>(method.toJS, <JSAny?>[
              args.jsify(),
            ]);
    } catch (error) {
      throw _mapWebError(method: method, error: error);
    }
  }

  bool _isThenable(final JSAny? value) {
    if (value == null) {
      return false;
    }
    try {
      return (value as JSObject).has('then');
    } catch (_) {
      return false;
    }
  }

  Object? _normalizeResult(final Object? result) {
    if (result == null || result is num || result is bool || result is String) {
      return result;
    }
    if (result is List || result is Map) {
      return result;
    }
    try {
      return (result as JSAny).dartify();
    } catch (_) {
      return result;
    }
  }

  CloudKitBridgeException _mapWebError({
    required final String method,
    required final Object error,
  }) {
    if (error is CloudKitBridgeException) {
      return error;
    }

    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (lower.contains('auth') ||
        lower.contains('token') ||
        lower.contains('unauthor') ||
        lower.contains('redirect') ||
        lower.contains('signin')) {
      return CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.authentication,
        message: 'CloudKit web authentication required while calling $method.',
        details: <String, Object?>{
          'action': 'refresh_web_api_token_or_sign_in',
          'method': method,
          'rawError': raw,
        },
      );
    }

    if (lower.contains('network') ||
        lower.contains('offline') ||
        lower.contains('timeout')) {
      return CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.network,
        message: 'CloudKit web network failure while calling $method.',
        details: <String, Object?>{
          'action': 'retry_after_network_recovers',
          'method': method,
          'rawError': raw,
        },
      );
    }

    if (lower.contains('conflict') || lower.contains('serverrecordchanged')) {
      return CloudKitBridgeException(
        code: CloudKitBridgeErrorCode.conflict,
        message: 'CloudKit web conflict while calling $method.',
        details: <String, Object?>{'method': method, 'rawError': raw},
      );
    }

    return CloudKitBridgeException(
      code: CloudKitBridgeErrorCode.unknown,
      message: 'CloudKit web call failed for $method.',
      details: <String, Object?>{'method': method, 'rawError': raw},
    );
  }

  static Map<String, Object?> _mapOrEmpty(final Object? value) => value is Map
      ? Map<String, Object?>.from(value)
      : const <String, Object?>{};

  static Object? _fieldValue(final Object? raw) {
    if (raw is Map) {
      final map = Map<String, Object?>.from(raw);
      if (map.containsKey('value')) {
        return map['value'];
      }
    }
    return raw;
  }

  static String? _stringOrNull(final Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int _intOrZero(final Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static DateTime _parseDate(final Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc();
      }
      final epoch = int.tryParse(value);
      if (epoch != null) {
        return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
      }
    }
    if (value is Map) {
      final map = Map<String, Object?>.from(value);
      final nested = map['timestamp'] ?? map['value'];
      return _parseDate(nested);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

enum _CloudKitClientMode { uninitialized, adapter, native }
