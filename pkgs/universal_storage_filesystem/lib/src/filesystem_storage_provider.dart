import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

/// {@template filesystem_storage_provider}
/// A storage provider that uses the local file system for storage operations.
/// Supports both desktop/mobile (using dart:io).
///
/// This provider is not supported on web.
/// {@endtemplate}
class FileSystemStorageProvider extends StorageProvider {
  /// {@macro filesystem_storage_provider}
  FileSystemStorageProvider();
  FileSystemConfig _config = FileSystemConfig.empty;
  String get _basePath => _config.basePath;
  var _isInitialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! FileSystemConfig) {
      throw ArgumentError(
        'Expected FileSystemConfig, got ${config.runtimeType}',
      );
    }

    _config = config;

    // Ensure the base directory exists
    final directory = await resolvePlatformDirectoryOfConfig(
      config.filePathConfig,
    );
    if (directory != null && !directory.existsSync()) {
      await directory.create(recursive: true);
    }

    _isInitialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _isInitialized;

  @override
  Future<FileOperationResult> createFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath, filePath);
    final file = File(fullPath);

    // Check if file already exists
    if (file.existsSync()) {
      throw FileAlreadyExistsException(
        'File already exists at path: $filePath',
      );
    }

    // Ensure parent directory exists
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    await file.writeAsString(content);
    return FileOperationResult.created(path: fullPath);
  }

  @override
  Future<String?> getFile(final String filePath) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      return null;
    }

    try {
      return await file.readAsString();
    } catch (e) {
      throw NetworkException('Failed to read file at $filePath: $e');
    }
  }

  @override
  Future<FileOperationResult> updateFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    await file.writeAsString(content);
    return FileOperationResult.updated(path: fullPath);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String filePath, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    await file.delete();
    return FileOperationResult.deleted(path: fullPath);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath, directoryPath);
    final directory = Directory(fullPath);

    if (!directory.existsSync()) {
      // Align provider behavior: return empty list for missing directories
      return <FileEntry>[];
    }

    final entities = await directory.list().toList();
    final items = <FileEntry>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final name = path.relative(entity.path, from: _basePath);
      items.add(
        FileEntry(
          name: name,
          isDirectory: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return items;
  }

  @override
  Future<void> restore(final String filePath, {final String? versionId}) {
    // For filesystem provider, restore is not meaningful without version
    // control. This could be extended to support backup/snapshot functionality.
    throw const UnsupportedOperationException(
      'Restore operation is not supported by FileSystemStorageProvider. '
      'Consider using OfflineGitStorageProvider for version control features.',
    );
  }

  @override
  bool get supportsSync => false;

  void _ensureInitialized() {
    if (!_isInitialized || _config.isEmpty) {
      throw const AuthenticationException(
        'Provider not initialized. Call init() first.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    await disposePathOfFileConfig(_config.filePathConfig);
    _config = FileSystemConfig.empty;
  }
}
