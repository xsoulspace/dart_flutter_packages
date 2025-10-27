import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import 'universal_storage_db.dart';

/// {@template storage_operation_data_type}
/// Represents the data type for storage operations.
///
/// Used internally to route operations to appropriate file handlers.
/// {@endtemplate}
enum _StorageOperationDataType {
  /// Boolean operations
  oBool,

  /// Integer operations
  oInt,

  /// String operations
  oString,

  /// Map operations
  oMap,

  /// Map list operations
  oMapList,
}

/// {@template operation_key}
/// Represents the key for an operation.
/// {@endtemplate}
extension type const _OperationKey(String value) implements String {}

/// {@template local_db_universal_storage_impl}
/// Local DB Universal Storage implementation.
///
/// Provides persistent storage for various data types with configurable
/// file routing and caching. Supports bools, ints, strings, maps, and map
/// lists.
///
/// Example:
/// ```dart
/// final db = LocalDbUniversalStorageImpl(
///   storageConfig: StorageConfig(...),
///   config: const UniversalStorageDbConfig(),
/// );
/// await db.init();
/// await db.setBool(key: 'darkMode', value: true);
/// final isDark = await db.getBool(key: 'darkMode');
/// ```
/// {@endtemplate}
class LocalDbUniversalStorageImpl implements LocalDbI {
  /// {@macro local_db_universal_storage_impl}
  LocalDbUniversalStorageImpl({required this.db, this.subfolderPath = ''});

  /// {@template subfolder}
  /// Subfolder path for files.
  /// format:
  /// ```dart
  /// 'subfolder/'
  /// ```
  /// {@endtemplate}
  final String subfolderPath;

  /// {@macro universal_storage_db}
  final UniversalStorageDb db;
  StorageService get _storageService => db.storageService;

  /// {@macro universal_storage_db_config}
  UniversalStorageDbConfig get _config => db.config;
  final _singleFilesStringsCache = <_OperationKey, String>{};
  final _singleFilesIntsCache = <_OperationKey, int>{};
  final _singleFilesBoolsCache = <_OperationKey, bool>{};
  final _singleFilesMapsCache = <_OperationKey, Map<String, dynamic>>{};
  final _singleFilesMapListsCache =
      <_OperationKey, List<Map<String, dynamic>>>{};
  final _singleFilesStringsListsCache = <_OperationKey, List<String>>{};

  StorageRouterType get _routerTypes => _config.storageRouterTypes;

  @override
  Future<void> init() async {
    // maybe check or cache files?
  }

  String _getFileName({
    required final _StorageOperationDataType dataType,
    required final String key,
  }) {
    final fileName = switch (dataType) {
      _StorageOperationDataType.oBool =>
        _routerTypes.placeBoolsToOneFile
            ? _config.boolSingleFileNameBuilder(key)
            : _config.boolSeparateFileNameBuilder(key),
      _StorageOperationDataType.oInt =>
        _routerTypes.placeIntsToOneFile
            ? _config.intSingleFileNameBuilder(key)
            : _config.intSeparateFileNameBuilder(key),
      _StorageOperationDataType.oString =>
        _routerTypes.placeStringsToOneFile
            ? _config.stringSingleFileNameBuilder(key)
            : _config.stringSeparateFileNameBuilder(key),
      _StorageOperationDataType.oMap =>
        _routerTypes.placeSingleMapToOneFile
            ? _config.mapSingleFileNameBuilder(key)
            : _config.mapSeparateFileNameBuilder(key),
      _StorageOperationDataType.oMapList =>
        _routerTypes.placeMapListInSingleFile
            ? _config.mapListSingleFileNameBuilder(key)
            : _config.mapListSeparateFileNameBuilder(key),
    };
    return subfolderPath + fileName + db.config.fileExtension.withDot;
  }

  Future<String> _readContent({
    required final String key,
    required final _StorageOperationDataType dataType,
    final bool? createIfNotExists,
  }) async {
    final fileName = _getFileName(dataType: dataType, key: key);
    final file = await _storageService.readFile(fileName);
    if (file == null) {
      if (createIfNotExists ?? _config.createFileIfNotExists) {
        await _storageService.saveFile(fileName, '');
      }

      return '';
    }
    return file;
  }

  Future<void> _writeContent({
    required final String key,
    required final _StorageOperationDataType dataType,
    required final String content,
  }) async {
    final fileName = _getFileName(dataType: dataType, key: key);
    await _storageService.saveFile(fileName, content);
  }

  Map<String, T>? _getSingleFileCacheMap<T extends Object>({
    required final _StorageOperationDataType dataType,
  }) =>
      switch (dataType) {
            _StorageOperationDataType.oBool => _singleFilesBoolsCache,
            _StorageOperationDataType.oInt => _singleFilesIntsCache,
            _StorageOperationDataType.oString => _singleFilesStringsCache,
            _StorageOperationDataType.oMap => _singleFilesMapsCache,
            _StorageOperationDataType.oMapList => _singleFilesMapListsCache,
          }
          as Map<String, T>?;

  T? _getSingleFileCacheValue<T extends Object>({
    required final String key,
    required final _StorageOperationDataType dataType,
  }) => _getSingleFileCacheMap<T>(dataType: dataType)?[key];

  void _setSingleFileCacheMap<T extends Object>({
    required final _StorageOperationDataType dataType,
    required final String key,
    required final Map<String, T> map,
  }) {
    final opKey = _OperationKey(key);
    final _ = switch (dataType) {
      _StorageOperationDataType.oBool => _singleFilesBoolsCache,
      _StorageOperationDataType.oInt => _singleFilesIntsCache,
      _StorageOperationDataType.oString => _singleFilesStringsCache,
      _StorageOperationDataType.oMap => _singleFilesMapsCache,
      _StorageOperationDataType.oMapList => _singleFilesMapListsCache,
    }..[opKey] = map;
  }

  Future<T> _readKeyValueFromSingleFile<T extends Object>({
    required final String key,
    required final _StorageOperationDataType dataType,
    required final T defaultValue,
  }) async {
    final cached = _getSingleFileCacheValue<T>(key: key, dataType: dataType);
    if (cached != null) return cached;
    final content = await _readContent(key: key, dataType: dataType);
    if (content.isEmpty) return defaultValue;
    final map = jsonDecodeMapAs<String, T>(content);
    return map[key] ?? defaultValue;
  }

  Future<void> _writeKeyValueToSingleFile<T extends Object>({
    required final String key,
    required final _StorageOperationDataType dataType,
    required final T value,
  }) async {
    Future<Map<String, T>> getContent() async {
      final content = await _readContent(key: key, dataType: dataType);
      return jsonDecodeMapAs<String, T>(content);
    }

    final cacheMap = _getSingleFileCacheMap<T>(dataType: dataType);
    final map = cacheMap ?? await getContent();
    map[key] = value;
    _setSingleFileCacheMap(dataType: dataType, key: key, map: map);
    await _writeContent(key: key, dataType: dataType, content: jsonEncode(map));
  }

  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) => _readKeyValueFromSingleFile(
    key: key,
    dataType: _StorageOperationDataType.oBool,
    defaultValue: defaultValue,
  );

  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: _StorageOperationDataType.oBool,
    value: value,
  );

  @override
  Future<int> getInt({required final String key, final int defaultValue = 0}) =>
      _readKeyValueFromSingleFile(
        key: key,
        dataType: _StorageOperationDataType.oInt,
        defaultValue: defaultValue,
      );

  @override
  Future<void> setInt({required final String key, final int value = 0}) =>
      _writeKeyValueToSingleFile(
        key: key,
        dataType: _StorageOperationDataType.oInt,
        value: value,
      );

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic> p1) fromJson,
    required final T defaultValue,
  }) async {
    final map = await getMap(key);
    return fromJson(map) ?? defaultValue;
  }

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    final json = toJson(value);
    await setMap(key: key, value: json);
  }

  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic> p1) fromJson,
    final List<T> defaultValue = const [],
  }) async {
    final iterable = await getMapIterable(key: key, defaultValue: []);
    if (iterable.isEmpty) return defaultValue;
    return iterable.map(fromJson);
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) => setMapList(key: key, value: value.map(toJson).toList());

  @override
  Future<Map<String, dynamic>> getMap(final String key) =>
      _readKeyValueFromSingleFile(
        key: key,
        dataType: _StorageOperationDataType.oMap,
        defaultValue: {},
      );

  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: _StorageOperationDataType.oMap,
    value: value,
  );

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) async {
    final opKey = _OperationKey(key);
    final cached = _singleFilesMapListsCache[opKey];
    if (cached != null) return cached;
    final iterable = await _readContent(
      key: key,
      dataType: _StorageOperationDataType.oMapList,
    );
    if (iterable.isEmpty) return defaultValue;
    return _singleFilesMapListsCache[opKey] ??=
        jsonDecodeListAs<Map<String, dynamic>>(iterable);
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async {
    _singleFilesMapListsCache[_OperationKey(key)] = value;
    final json = jsonEncode(value);
    await _writeContent(
      key: key,
      dataType: _StorageOperationDataType.oMapList,
      content: json,
    );
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) => _readKeyValueFromSingleFile(
    key: key,
    dataType: _StorageOperationDataType.oString,
    defaultValue: defaultValue,
  );

  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: _StorageOperationDataType.oString,
    value: value,
  );

  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
  }) async {
    final opKey = _OperationKey(key);
    final cached = _singleFilesStringsListsCache[opKey];
    if (cached != null) return cached;
    final iterable = await _readContent(
      key: key,
      dataType: _StorageOperationDataType.oMapList,
    );
    if (iterable.isEmpty) return defaultValue;
    return _singleFilesStringsListsCache[opKey] ??= jsonDecodeListAs<String>(
      iterable,
    );
  }

  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) async {
    _singleFilesStringsListsCache[_OperationKey(key)] = value;
    final json = jsonEncode(value);
    await _writeContent(
      key: key,
      dataType: _StorageOperationDataType.oMapList,
      content: json,
    );
  }
}
