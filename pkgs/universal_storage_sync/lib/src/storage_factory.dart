import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';
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
    final provider = _createProvider(config);
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates the appropriate storage provider based on config type
  static StorageProvider _createProvider(final StorageConfig config) =>
      switch (config) {
        FileSystemConfig() => FileSystemStorageProvider(),
        GitHubApiConfig() => GitHubApiStorageProvider(),
        OfflineGitConfig() => OfflineGitStorageProvider(),
      };

  /// Creates a FileSystem storage service
  static Future<StorageService> createFileSystem(
    final FileSystemConfig config,
  ) async {
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates a GitHub API storage service
  static Future<StorageService> createGitHubApi(
    final GitHubApiConfig config,
  ) async {
    final provider = GitHubApiStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }

  /// Creates an Offline Git storage service
  static Future<StorageService> createOfflineGit(
    final OfflineGitConfig config,
  ) async {
    final provider = OfflineGitStorageProvider();
    await provider.initWithConfig(config);
    return StorageService(provider);
  }
}
