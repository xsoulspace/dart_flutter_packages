import 'package:path/path.dart' as path;
import 'package:universal_storage_sync/universal_storage_sync.dart';

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
/// Configuration for [LocalDbUniversalStorageImpl] storage operations.
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
    this.fileExtension = FileExtension.json,
  });

  /// {@template file_format}
  /// File format: use json or yaml
  /// {@endtemplate}
  final FileExtension fileExtension;

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

/// {@template universal_storage_db}
/// Universal Storage DB.
///
// TODO(arenukvern): add docs for this class
/// {@endtemplate}
class UniversalStorageDb {
  /// {@macro universal_storage_db}
  UniversalStorageDb({
    required this.storageConfig,
    this.config = const UniversalStorageDbConfig(),
  });
  late final StorageService storageService;
  final StorageConfig storageConfig;
  final UniversalStorageDbConfig config;

  Future<void> init() async {
    storageService = await StorageFactory.create(storageConfig);
  }

  void pickPathForConfig() {}
}
