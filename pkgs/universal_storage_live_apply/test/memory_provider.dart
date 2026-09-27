import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Minimal in-memory [StorageProvider] for unit tests: no persistence, exact
/// string semantics, honest exceptions.
class MemoryStorageProvider extends StorageProvider {
  final Map<String, String> files = <String, String>{};

  @override
  Future<void> initWithConfig(final StorageConfig config) async {}

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    if (files.containsKey(path)) {
      throw const FileAlreadyExistsException('already exists');
    }
    files[path] = content;
    return FileOperationResult(path: path, isNew: true);
  }

  @override
  Future<String?> getFile(final String path) async => files[path];

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    if (!files.containsKey(path)) {
      throw const FileNotFoundException('missing');
    }
    files[path] = content;
    return FileOperationResult(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    if (!files.containsKey(path)) {
      throw const FileNotFoundException('missing');
    }
    files.remove(path);
    return FileOperationResult(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async =>
      files.keys
          .map((final f) => FileEntry(name: f, isDirectory: false))
          .toList();

  @override
  Future<void> restore(
    final String path, {
    final String? versionId,
  }) async {
    throw const UnsupportedOperationException('no restore in the fake');
  }

  @override
  Future<void> dispose() async {}
}
