import 'dart:developer';

import 'exceptions.dart';
import 'models/models.dart';
import 'storage_service_contracts.dart';

/// {@template storage_service}
/// A service class providing a unified API for file storage operations
/// using a configured [StorageProvider].
/// {@endtemplate}
class StorageService {
  /// {@macro storage_service}
  StorageService(this._provider);
  final StorageProvider _provider;

  /// {@template storage_service.initializeWithConfig}
  /// Initializes the underlying storage provider with typed [config].
  /// Must be called before other operations.
  /// Provides better type safety than the legacy [initialize] method.
  /// {@endtemplate}
  Future<void> initializeWithConfig(final StorageConfig config) =>
      _provider.initWithConfig(config);

  /// {@template storage_service.saveFile}
  /// Saves (creates or updates) a file at [path] with [content].
  /// Uses [message] as commit message for version-controlled storage.
  /// {@endtemplate}
  Future<FileOperationResult> saveFile(
    final String path,
    final String content, {
    final String? message,
  }) async {
    try {
      final existingContent = await _provider.getFile(path);
      if (existingContent != null) {
        return _provider.updateFile(path, content, commitMessage: message);
      } else {
        return _provider.createFile(path, content, commitMessage: message);
      }
    } on FileNotFoundException {
      return _provider.createFile(path, content, commitMessage: message);
    }
  }

  /// {@template storage_service.readFile}
  /// Reads content of file at [path]. Returns `null` if not found.
  /// {@endtemplate}
  Future<String?> readFile(final String path) => _provider.getFile(path);

  /// {@template storage_service.removeFile}
  /// Removes file at [path]. [message] for version-controlled storage.
  /// {@endtemplate}
  Future<FileOperationResult> removeFile(
    final String path, {
    final String? message,
  }) => _provider.deleteFile(path, commitMessage: message);

  /// {@template storage_service.listDirectory}
  /// Lists files/subdirectories within [path].
  /// {@endtemplate}
  Future<List<FileEntry>> listDirectory(final String path) =>
      _provider.listDirectory(path);

  /// {@template storage_service.restoreData}
  /// Restores data at [path], optionally to [versionId].
  /// {@endtemplate}
  Future<void> restoreData(final String path, {final String? versionId}) =>
      _provider.restore(path, versionId: versionId);

  /// {@template storage_service.syncRemote}
  /// Synchronizes local data with the configured remote storage provider,
  /// if supported.
  /// {@endtemplate}
  Future<void> syncRemote({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    if (_provider.supportsSync) {
      await _provider.sync(
        pullMergeStrategy: pullMergeStrategy,
        pushConflictStrategy: pushConflictStrategy,
      );
    } else {
      // Log or handle providers not supporting sync
      log(
        'The configured storage provider does not support remote '
        'synchronization.',
      );
      // Optionally throw UnsupportedOperationException
    }
  }

  /// Gets the underlying storage provider for advanced operations
  StorageProvider get provider => _provider;

  /// Checks if the provider is authenticated
  Future<bool> isAuthenticated() => _provider.isAuthenticated();
}
