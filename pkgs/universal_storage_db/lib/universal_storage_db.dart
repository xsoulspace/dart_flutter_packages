import 'dart:convert';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

class StorageRouterType {
  const StorageRouterType({
    this.placeBoolsToOneFile = true,
    this.placeIntsToOneFile = true,
    this.placeStringsToOneFile = true,
    this.placeSingleMapToOneFile = true,
    this.placeMapsInListAsSeparateFiles = true,
  });
  final bool placeBoolsToOneFile;
  final bool placeIntsToOneFile;
  final bool placeStringsToOneFile;
  final bool placeSingleMapToOneFile;
  final bool placeMapsInListAsSeparateFiles;
}

const kDefaultBoolFileName = 'xsun_b';
const kDefaultIntFileName = 'xsun_i';
const kDefaultStringFileName = 'xsun_s';
const kDefaultMapFileName = 'xsun_m';
const kDefaultMapListFileName = 'xsun_ml';

typedef StorageRouterFileBuilder = String Function(String key);

String defaultBoolSeparateFileNameBuilder(final String key) =>
    '${kDefaultBoolFileName}_$key';
String defaultBoolSingleFileNameBuilder(final String key) =>
    '${kDefaultBoolFileName}_single';

String defaultIntSeparateFileNameBuilder(final String key) =>
    '${kDefaultIntFileName}_$key';
String defaultIntSingleFileNameBuilder(final String key) =>
    '${kDefaultIntFileName}_single';

String defaultStringSeparateFileNameBuilder(final String key) =>
    '${kDefaultStringFileName}_$key';
String defaultStringSingleFileNameBuilder(final String key) =>
    '${kDefaultStringFileName}_single';

String defaultMapSeparateFileNameBuilder(final String key) =>
    '${kDefaultMapFileName}_$key';
String defaultMapSingleFileNameBuilder(final String key) =>
    '${kDefaultMapFileName}_single';

String defaultMapListSeparateFileNameBuilder(final String key) =>
    '${kDefaultMapListFileName}_$key';
String defaultMapListSingleFileNameBuilder(final String key) =>
    '${kDefaultMapListFileName}_single';

class UniversalStorageDbConfig {
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
  final StorageRouterType storageRouterTypes;

  /// default for all operations
  final bool createFileIfNotExists;
  final StorageRouterFileBuilder boolSeparateFileNameBuilder;
  final StorageRouterFileBuilder boolSingleFileNameBuilder;
  final StorageRouterFileBuilder intSeparateFileNameBuilder;
  final StorageRouterFileBuilder intSingleFileNameBuilder;
  final StorageRouterFileBuilder stringSeparateFileNameBuilder;
  final StorageRouterFileBuilder stringSingleFileNameBuilder;
  final StorageRouterFileBuilder mapSeparateFileNameBuilder;
  final StorageRouterFileBuilder mapSingleFileNameBuilder;
  final StorageRouterFileBuilder mapListSingleFileNameBuilder;
  final StorageRouterFileBuilder mapListSeparateFileNameBuilder;
}

enum StorageOperationDataType { oBool, oInt, oString, oMap, oMapList }

extension type const _FileName(String value) implements String {}
extension type const _OperationKey(String value) implements String {}

class UniversalStorageDb implements LocalDbI {
  UniversalStorageDb({
    required this.storageConfig,
    this.config = const UniversalStorageDbConfig(),
  });
  late final StorageService _storageService;
  final UniversalStorageDbConfig config;
  final _singleFilesStringsCache = <_OperationKey, String>{};
  final _singleFilesIntsCache = <_OperationKey, int>{};
  final _singleFilesBoolsCache = <_OperationKey, bool>{};
  final _singleFilesMapsCache = <_OperationKey, Map<String, dynamic>>{};
  final _singleFilesMapListsCache =
      <_OperationKey, List<Map<String, dynamic>>>{};

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
      _routerTypes.placeMapsInListAsSeparateFiles
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
  }) {
    // TODO: implement getItemsIterable
    throw UnimplementedError();
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) {
    // TODO: implement setItemsList
    throw UnimplementedError();
  }

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
  }) {
    if (_routerTypes.placeMapsInListAsSeparateFiles) {
    } else {}
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) {
    // TODO: implement setMapList
    throw UnimplementedError();
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
  }) {
    // TODO: implement getStringsIterable
    throw UnimplementedError();
  }

  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) {
    // TODO: implement setStringList
    throw UnimplementedError();
  }
}
