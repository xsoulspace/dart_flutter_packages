import 'exceptions.dart';
import 'models/file_models.dart';
import 'models/storage_config.dart';

/// Provider-agnostic contract for storage operations.
abstract class StorageProvider {
  Future<void> initWithConfig(final StorageConfig config);
  Future<bool> isAuthenticated();

  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  });

  Future<String?> getFile(final String path);

  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  });

  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  });

  Future<List<FileEntry>> listDirectory(final String directoryPath);

  Future<void> restore(final String path, {final String? versionId});

  bool get supportsSync => false;

  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) {
    throw const UnsupportedOperationException(
      'This provider does not support sync.',
    );
  }
}
