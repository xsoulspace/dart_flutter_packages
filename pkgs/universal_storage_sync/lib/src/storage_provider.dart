import 'models/models.dart';
import 'storage_exceptions.dart';

/// {@template storage_provider}
/// Defines the contract for a storage provider.
/// {@endtemplate}
abstract class StorageProvider {
  /// {@template storage_provider.initWithConfig}
  /// Initializes the storage provider with the given typed [config].
  /// This method provides better type safety than legacy implementations.
  /// {@endtemplate}
  Future<void> initWithConfig(final StorageConfig config);

  /// {@template storage_provider.isAuthenticated}
  /// Checks if the provider is currently authenticated or properly configured.
  /// {@endtemplate}
  Future<bool> isAuthenticated();

  /// {@template storage_provider.createFile}
  /// Creates a new file at [path] with [content].
  /// For version-controlled providers, an optional [commitMessage]
  /// can be provided.
  /// {@endtemplate}
  Future<String> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  });

  /// {@template storage_provider.getFile}
  /// Retrieves the content of the file at [path]. Returns `null` if not found.
  /// {@endtemplate}
  Future<String?> getFile(final String path);

  /// {@template storage_provider.updateFile}
  /// Updates an existing file at [path] with new [content].
  /// An optional [commitMessage] can be provided for
  /// version-controlled providers.
  /// {@endtemplate}
  Future<String> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  });

  /// {@template storage_provider.deleteFile}
  /// Deletes the file at [path].
  /// An optional [commitMessage] can be provided for
  /// version-controlled providers.
  /// {@endtemplate}
  Future<void> deleteFile(final String path, {final String? commitMessage});

  /// {@template storage_provider.listFiles}
  /// Lists all files and directories within the specified [directoryPath].
  /// {@endtemplate}
  Future<List<String>> listFiles(final String directoryPath);

  /// {@template storage_provider.restore}
  /// Restores a file or set of files. Behavior is provider-dependent.
  /// [versionId] can specify a version (e.g., Git commit hash).
  /// {@endtemplate}
  Future<void> restore(final String path, {final String? versionId});

  /// {@template storage_provider.supportsSync}
  /// Indicates if the provider supports remote
  /// synchronization. Defaults to `false`.
  /// {@endtemplate}
  bool get supportsSync => false;

  /// {@template storage_provider.sync}
  /// Synchronizes with a remote store, if applicable.
  /// Throws [UnsupportedOperationException] if not supported.
  /// [pullMergeStrategy] and [pushConflictStrategy] can guide behavior.
  /// {@endtemplate}
  Future<void> sync({
    final String? pullMergeStrategy, // e.g., 'rebase', 'merge', 'ff-only'
    final String?
    pushConflictStrategy, // e.g., 'rebase-local', 'force-with-lease'
  }) {
    throw const UnsupportedOperationException(
      'This provider does not support sync.',
    );
  }
}
