import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'storage_provider_registry.dart';
import 'storage_service.dart';

/// {@template storage_factory}
/// Factory class for creating configured storage services.
/// Automatically determines the provider type based on configuration
/// and returns a ready-to-use StorageService.
/// {@endtemplate}
mixin StorageFactory {
  /// Creates a StorageService with the appropriate provider based on
  /// [config] type.
  /// The returned service is already initialized and ready to use.
  static Future<StorageService> create(final StorageConfig config) async {
    final provider = StorageProviderRegistry.resolve(config);
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates the appropriate storage provider based on config type
  static StorageProvider _createProvider(final StorageConfig config) =>
      StorageProviderRegistry.resolve(config);

  /// Creates a FileSystem storage service
  static Future<StorageService> createFileSystem(
    final FileSystemConfig config,
  ) async => create(config);

  /// Creates a GitHub API storage service
  static Future<StorageService> createGitHubApi(
    final GitHubApiConfig config,
  ) async => create(config);

  /// Creates an Offline Git storage service
  static Future<StorageService> createOfflineGit(
    final OfflineGitConfig config,
  ) async => create(config);
}
