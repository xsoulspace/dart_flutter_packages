import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

/// {@template storage_router_type}
/// Configuration for routing storage operations to appropriate file structures.
///
/// Controls whether data types (bools, ints, strings, maps) should be stored
/// in a single file or separate files per key.
/// {@endtemplate}
class StorageRouterType {
  /// {@macro storage_router_type}
  const StorageRouterType({
    this.placeBoolsToOneFile = true,
    this.placeIntsToOneFile = true,
    this.placeStringsToOneFile = true,
    this.placeSingleMapToOneFile = true,
    this.placeMapListInSingleFile = true,
  });

  /// Whether to place all bool values in a single file.
  final bool placeBoolsToOneFile;

  /// Whether to place all int values in a single file.
  final bool placeIntsToOneFile;

  /// Whether to place all string values in a single file.
  final bool placeStringsToOneFile;

  /// Whether to place all map values in a single file.
  final bool placeSingleMapToOneFile;

  /// Whether to place map list values in a single file.
  final bool placeMapListInSingleFile;
}

/// {@template default_bool_file_name}
/// Default file name for bool values.
/// {@endtemplate}
const kDefaultBoolFileName = 'xsun_b';

/// {@template default_int_file_name}
/// Default file name for int values.
/// {@endtemplate}
const kDefaultIntFileName = 'xsun_i';

/// {@template default_string_file_name}
/// Default file name for string values.
/// {@endtemplate}
const kDefaultStringFileName = 'xsun_s';

/// {@template default_map_file_name}
/// Default file name for map values.
/// {@endtemplate}
const kDefaultMapFileName = 'xsun_m';

/// {@template default_map_list_file_name}
/// Default file name for map list values.
/// {@endtemplate}
const kDefaultMapListFileName = 'xsun_ml';

/// {@template storage_router_file_builder}
/// Function to generate file names for storage operations.
///
/// Takes a key and returns the appropriate file name for that key.
/// {@endtemplate}
typedef StorageRouterFileBuilder = String Function(String key);

/// {@macro storage_router_file_builder}
String defaultBoolSeparateFileNameBuilder(final String key) =>
    '${kDefaultBoolFileName}_$key';

/// {@macro storage_router_file_builder}
String defaultBoolSingleFileNameBuilder(final String key) =>
    '${kDefaultBoolFileName}_single';

/// {@macro storage_router_file_builder}
String defaultIntSeparateFileNameBuilder(final String key) =>
    '${kDefaultIntFileName}_$key';

/// {@macro storage_router_file_builder}
String defaultIntSingleFileNameBuilder(final String key) =>
    '${kDefaultIntFileName}_single';

/// {@macro storage_router_file_builder}
String defaultStringSeparateFileNameBuilder(final String key) =>
    '${kDefaultStringFileName}_$key';

/// {@macro storage_router_file_builder}
String defaultStringSingleFileNameBuilder(final String key) =>
    '${kDefaultStringFileName}_single';

/// {@macro storage_router_file_builder}
String defaultMapSeparateFileNameBuilder(final String key) =>
    '${kDefaultMapFileName}_$key';

/// {@macro storage_router_file_builder}
String defaultMapSingleFileNameBuilder(final String key) =>
    '${kDefaultMapFileName}_single';

/// {@macro storage_router_file_builder}
String defaultMapListSeparateFileNameBuilder(final String key) =>
    '${kDefaultMapListFileName}_$key';

/// {@macro storage_router_file_builder}
String defaultMapListSingleFileNameBuilder(final String key) =>
    '${kDefaultMapListFileName}_single';

/// {@template universal_storage_db_config}
/// Configuration for [UniversalStorageDb] storage operations.
///
/// Controls file naming strategies, routing behavior, and default settings
/// for the universal storage database.
/// {@endtemplate}
class UniversalStorageDbConfig {
  /// {@macro universal_storage_db_config}
  const UniversalStorageDbConfig({
    this.storageRouterTypes = const StorageRouterType(),
    this.boolSeparateFileNameBuilder = defaultBoolSeparateFileNameBuilder,
    this.boolSingleFileNameBuilder = defaultBoolSingleFileNameBuilder,
    this.intSeparateFileNameBuilder = defaultIntSeparateFileNameBuilder,
    this.intSingleFileNameBuilder = defaultIntSingleFileNameBuilder,
    this.stringSeparateFileNameBuilder = defaultStringSeparateFileNameBuilder,
    this.stringSingleFileNameBuilder = defaultStringSingleFileNameBuilder,
    this.mapSeparateFileNameBuilder = defaultMapSeparateFileNameBuilder,
    this.mapSingleFileNameBuilder = defaultMapSingleFileNameBuilder,
    this.mapListSeparateFileNameBuilder = defaultMapListSeparateFileNameBuilder,
    this.mapListSingleFileNameBuilder = defaultMapListSingleFileNameBuilder,
    this.createFileIfNotExists = true,
  });

  /// {@macro storage_router_type}
  /// Configuration for routing storage operations.
  final StorageRouterType storageRouterTypes;

  /// Whether to create files if they don't exist during read operations.
  final bool createFileIfNotExists;

  /// {@macro storage_router_file_builder}
  /// Builder for separate bool file names.
  final StorageRouterFileBuilder boolSeparateFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for single bool file names.
  final StorageRouterFileBuilder boolSingleFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for separate int file names.
  final StorageRouterFileBuilder intSeparateFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for single int file names.
  final StorageRouterFileBuilder intSingleFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for separate string file names.
  final StorageRouterFileBuilder stringSeparateFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for single string file names.
  final StorageRouterFileBuilder stringSingleFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for separate map file names.
  final StorageRouterFileBuilder mapSeparateFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for single map file names.
  final StorageRouterFileBuilder mapSingleFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for single map list file names.
  final StorageRouterFileBuilder mapListSingleFileNameBuilder;

  /// {@macro storage_router_file_builder}
  /// Builder for separate map list file names.
  final StorageRouterFileBuilder mapListSeparateFileNameBuilder;
}

/// {@template storage_operation_data_type}
/// Represents the data type for storage operations.
///
/// Used internally to route operations to appropriate file handlers.
/// {@endtemplate}
enum StorageOperationDataType {
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

/// {@template universal_storage_db}
/// Universal storage database implementation.
///
/// Provides persistent storage for various data types with configurable
/// file routing and caching. Supports bools, ints, strings, maps, and map
/// lists.
///
/// Example:
/// ```dart
/// final db = UniversalStorageDb(
///   storageConfig: StorageConfig(...),
///   config: const UniversalStorageDbConfig(),
/// );
/// await db.init();
/// await db.setBool(key: 'darkMode', value: true);
/// final isDark = await db.getBool(key: 'darkMode');
/// ```
/// {@endtemplate}
class UniversalStorageDb implements LocalDbI {
  /// {@macro universal_storage_db}
  UniversalStorageDb({
    required this.storageConfig,
    this.config = const UniversalStorageDbConfig(),
  });
  late final StorageService _storageService;

  /// {@macro universal_storage_db_config}
  final UniversalStorageDbConfig config;
  final _singleFilesStringsCache = <_OperationKey, String>{};
  final _singleFilesIntsCache = <_OperationKey, int>{};
  final _singleFilesBoolsCache = <_OperationKey, bool>{};
  final _singleFilesMapsCache = <_OperationKey, Map<String, dynamic>>{};
  final _singleFilesMapListsCache =
      <_OperationKey, List<Map<String, dynamic>>>{};
  final _singleFilesStringsListsCache = <_OperationKey, List<String>>{};

  StorageRouterType get _routerTypes => config.storageRouterTypes;

  /// The storage config to use for the database.
  final StorageConfig storageConfig;
  @override
  Future<void> init() async {
    _storageService = await StorageFactory.create(storageConfig);
  }

  String _getFileName({
    required final StorageOperationDataType dataType,
    required final String key,
  }) => switch (dataType) {
    StorageOperationDataType.oBool =>
      _routerTypes.placeBoolsToOneFile
          ? config.boolSingleFileNameBuilder(key)
          : config.boolSeparateFileNameBuilder(key),
    StorageOperationDataType.oInt =>
      _routerTypes.placeIntsToOneFile
          ? config.intSingleFileNameBuilder(key)
          : config.intSeparateFileNameBuilder(key),
    StorageOperationDataType.oString =>
      _routerTypes.placeStringsToOneFile
          ? config.stringSingleFileNameBuilder(key)
          : config.stringSeparateFileNameBuilder(key),
    StorageOperationDataType.oMap =>
      _routerTypes.placeSingleMapToOneFile
          ? config.mapSingleFileNameBuilder(key)
          : config.mapSeparateFileNameBuilder(key),
    StorageOperationDataType.oMapList =>
      _routerTypes.placeMapListInSingleFile
          ? config.mapListSingleFileNameBuilder(key)
          : config.mapListSeparateFileNameBuilder(key),
  };

  Future<String> _readContent({
    required final String key,
    required final StorageOperationDataType dataType,
    final bool? createIfNotExists,
  }) async {
    final fileName = _getFileName(dataType: dataType, key: key);
    final file = await _storageService.readFile(fileName);
    if (file == null) {
      if (createIfNotExists ?? config.createFileIfNotExists) {
        await _storageService.saveFile(fileName, '');
      }

      return '';
    }
    return file;
  }

  Future<void> _writeContent({
    required final String key,
    required final StorageOperationDataType dataType,
    required final String content,
  }) async {
    final fileName = _getFileName(dataType: dataType, key: key);
    await _storageService.saveFile(fileName, content);
  }

  Map<String, T>? _getSingleFileCacheMap<T extends Object>({
    required final StorageOperationDataType dataType,
  }) =>
      switch (dataType) {
            StorageOperationDataType.oBool => _singleFilesBoolsCache,
            StorageOperationDataType.oInt => _singleFilesIntsCache,
            StorageOperationDataType.oString => _singleFilesStringsCache,
            StorageOperationDataType.oMap => _singleFilesMapsCache,
            StorageOperationDataType.oMapList => _singleFilesMapListsCache,
          }
          as Map<String, T>?;

  T? _getSingleFileCacheValue<T extends Object>({
    required final String key,
    required final StorageOperationDataType dataType,
  }) => _getSingleFileCacheMap<T>(dataType: dataType)?[key];

  void _setSingleFileCacheMap<T extends Object>({
    required final StorageOperationDataType dataType,
    required final String key,
    required final Map<String, T> map,
  }) {
    final opKey = _OperationKey(key);
    final _ = switch (dataType) {
      StorageOperationDataType.oBool => _singleFilesBoolsCache,
      StorageOperationDataType.oInt => _singleFilesIntsCache,
      StorageOperationDataType.oString => _singleFilesStringsCache,
      StorageOperationDataType.oMap => _singleFilesMapsCache,
      StorageOperationDataType.oMapList => _singleFilesMapListsCache,
    }..[opKey] = map;
  }

  Future<T> _readKeyValueFromSingleFile<T extends Object>({
    required final String key,
    required final StorageOperationDataType dataType,
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
    required final StorageOperationDataType dataType,
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
    dataType: StorageOperationDataType.oBool,
    defaultValue: defaultValue,
  );

  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: StorageOperationDataType.oBool,
    value: value,
  );

  @override
  Future<int> getInt({required final String key, final int defaultValue = 0}) =>
      _readKeyValueFromSingleFile(
        key: key,
        dataType: StorageOperationDataType.oInt,
        defaultValue: defaultValue,
      );

  @override
  Future<void> setInt({required final String key, final int value = 0}) =>
      _writeKeyValueToSingleFile(
        key: key,
        dataType: StorageOperationDataType.oInt,
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
        dataType: StorageOperationDataType.oMap,
        defaultValue: {},
      );

  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: StorageOperationDataType.oMap,
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
      dataType: StorageOperationDataType.oMapList,
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
      dataType: StorageOperationDataType.oMapList,
      content: json,
    );
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) => _readKeyValueFromSingleFile(
    key: key,
    dataType: StorageOperationDataType.oString,
    defaultValue: defaultValue,
  );

  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) => _writeKeyValueToSingleFile(
    key: key,
    dataType: StorageOperationDataType.oString,
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
      dataType: StorageOperationDataType.oMapList,
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
      dataType: StorageOperationDataType.oMapList,
      content: json,
    );
  }
}
