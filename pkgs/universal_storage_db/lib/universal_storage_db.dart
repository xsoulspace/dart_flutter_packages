import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

class StorageRouterType {
  const StorageRouterType({
    this.placeBoolsToOneFile = true,
    this.placeIntsToOneFile = true,
    this.placeMapsToSeparateFiles = true,
    this.placeStringToOneFile = true,
  });
  final bool placeBoolsToOneFile;
  final bool placeIntsToOneFile;
  final bool placeStringToOneFile;
  final bool placeMapsToSeparateFiles;
}

typedef StorageRouterFileBuilder = String Function(String key);

String defaultBoolFileNameBuilder(final String key) => 'xsun_b_$key';
String defaultIntFileNameBuilder(final String key) => 'xsun_i_$key';
String defaultStringFileNameBuilder(final String key) => 'xsun_s_$key';
String defaultMapFileNameBuilder(final String key) => 'xsun_m_$key';

class UniversalStorageDbConfig {
  const UniversalStorageDbConfig({
    this.storageRouterTypes = const StorageRouterType(),
    this.boolFileNameBuilder = defaultBoolFileNameBuilder,
    this.intFileNameBuilder = defaultIntFileNameBuilder,
    this.stringFileNameBuilder = defaultStringFileNameBuilder,
    this.mapFileNameBuilder = defaultMapFileNameBuilder,
  });
  final StorageRouterType storageRouterTypes;
  final StorageRouterFileBuilder boolFileNameBuilder;
  final StorageRouterFileBuilder intFileNameBuilder;
  final StorageRouterFileBuilder stringFileNameBuilder;
  final StorageRouterFileBuilder mapFileNameBuilder;
}

class UniversalStorageDb implements LocalDbI {
  UniversalStorageDb({
    required this.storageConfig,
    this.config = const UniversalStorageDbConfig(),
  });
  late final StorageService _storageService;
  final UniversalStorageDbConfig config;
  StorageRouterType get _routerTypes => config.storageRouterTypes;
  static const defaultBoolFileName = 'xsun_b';
  static const defaultIntFileName = 'xsun_i';
  static const defaultStringFileName = 'xsun_s';
  static const defaultMapFileName = 'xsun_m';

  /// The storage config to use for the database.
  final StorageConfig storageConfig;
  @override
  Future<void> init() async {
    _storageService = await StorageFactory.create(storageConfig);
  }

  Future<String> _readOrCreateFile(final String fileName) async {
    final file = await _storageService.readFile(fileName);
    if (file == null) {
      await _storageService.saveFile(fileName, '');
      return '';
    }
    return file;
  }

  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) {
    final fileName = config.boolFileNameBuilder(key);
    if (_routerTypes.placeBoolsToOneFile) {
      return _storageService.readFile(fileName);
    } else {
      throw UnimplementedError();
    }
    // TODO: implement getBool
    throw UnimplementedError();
  }

  @override
  Future<int> getInt({required final String key, final int defaultValue = 0}) {
    // TODO: implement getInt
    throw UnimplementedError();
  }

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic> p1) fromJson,
    required final T defaultValue,
  }) {
    // TODO: implement getItem
    throw UnimplementedError();
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
  Future<Map<String, dynamic>> getMap(final String key) {
    // TODO: implement getMap
    throw UnimplementedError();
  }

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) {
    // TODO: implement getMapIterable
    throw UnimplementedError();
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) {
    // TODO: implement getString
    throw UnimplementedError();
  }

  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
  }) {
    // TODO: implement getStringsIterable
    throw UnimplementedError();
  }

  @override
  Future<void> setBool({required final String key, required final bool value}) {
    // TODO: implement setBool
    throw UnimplementedError();
  }

  @override
  Future<void> setInt({required final String key, final int value = 0}) {
    // TODO: implement setInt
    throw UnimplementedError();
  }

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) {
    // TODO: implement setItem
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
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) {
    // TODO: implement setMap
    throw UnimplementedError();
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
  Future<void> setString({
    required final String key,
    required final String value,
  }) {
    // TODO: implement setString
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
