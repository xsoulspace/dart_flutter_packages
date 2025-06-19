import 'config/storage_config.dart';
import 'exceptions/storage_exceptions.dart';
import 'providers/filesystem_storage_provider.dart';
import 'providers/github_api_storage_provider.dart';
import 'providers/offline_git_storage_provider.dart';
import 'storage_provider.dart';
import 'storage_service.dart';

/// {@template storage_factory}
/// Factory class for creating configured storage services.
/// Automatically determines the provider type based on configuration
/// and returns a ready-to-use StorageService.
/// {@endtemplate}
class StorageFactory {
  /// {@macro storage_factory}
  const StorageFactory();

  /// Creates a StorageService with the appropriate provider based on [config] type.
  /// The returned service is already initialized and ready to use.
  static Future<StorageService> create(StorageConfig config) async {
    final provider = _createProvider(config);
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates the appropriate storage provider based on config type
  static StorageProvider _createProvider(StorageConfig config) {
    switch (config.runtimeType) {
      case FileSystemConfig:
        return FileSystemStorageProvider();
      case GitHubApiConfig:
        return GitHubApiStorageProvider();
      case OfflineGitConfig:
        return OfflineGitStorageProvider();
      default:
        throw ConfigurationException(
          'Unsupported configuration type: ${config.runtimeType}',
        );
    }
  }

  /// Creates a FileSystem storage service
  static Future<StorageService> createFileSystem(
      FileSystemConfig config) async {
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates a GitHub API storage service
  static Future<StorageService> createGitHubApi(GitHubApiConfig config) async {
    final provider = GitHubApiStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates an Offline Git storage service
  static Future<StorageService> createOfflineGit(
      OfflineGitConfig config) async {
    final provider = OfflineGitStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }
}
