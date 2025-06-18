import 'exceptions/storage_exceptions.dart';
import 'storage_provider.dart';

/// {@template storage_service}
/// A service class providing a unified API for file storage operations
/// using a configured [StorageProvider].
/// {@endtemplate}
class StorageService {
  final StorageProvider _provider;

  /// {@macro storage_service}
  StorageService(this._provider);

  /// {@template storage_service.initialize}
  /// Initializes the underlying storage provider with [config].
  /// Must be called before other operations.
  /// {@endtemplate}
  Future<void> initialize(Map<String, dynamic> config) =>
      _provider.init(config);

  /// {@template storage_service.saveFile}
  /// Saves (creates or updates) a file at [path] with [content].
  /// Uses [message] as commit message for version-controlled storage.
  /// {@endtemplate}
  Future<String> saveFile(
    String path,
    String content, {
    String? message,
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
  Future<String?> readFile(String path) => _provider.getFile(path);

  /// {@template storage_service.removeFile}
  /// Removes file at [path]. [message] for version-controlled storage.
  /// {@endtemplate}
  Future<void> removeFile(String path, {String? message}) =>
      _provider.deleteFile(path, commitMessage: message);

  /// {@template storage_service.listDirectory}
  /// Lists files/subdirectories within [path].
  /// {@endtemplate}
  Future<List<String>> listDirectory(String path) => _provider.listFiles(path);

  /// {@template storage_service.restoreData}
  /// Restores data at [path], optionally to [versionId].
  /// {@endtemplate}
  Future<void> restoreData(String path, {String? versionId}) =>
      _provider.restore(path, versionId: versionId);

  /// {@template storage_service.syncRemote}
  /// Synchronizes local data with the configured remote storage provider,
  /// if supported.
  /// {@endtemplate}
  Future<void> syncRemote({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  }) async {
    if (_provider.supportsSync) {
      await _provider.sync(
        pullMergeStrategy: pullMergeStrategy,
        pushConflictStrategy: pushConflictStrategy,
      );
    } else {
      // Log or handle providers not supporting sync
      print(
        'The configured storage provider does not support remote synchronization.',
      );
      // Optionally throw UnsupportedOperationException
    }
  }
}
