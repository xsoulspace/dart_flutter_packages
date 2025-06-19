import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions/storage_exceptions.dart';
import '../storage_provider.dart';

/// {@template filesystem_storage_provider}
/// A storage provider that uses the local file system for storage operations.
/// Supports both desktop/mobile (using dart:io) and web (using IndexedDB simulation).
/// {@endtemplate}
class FileSystemStorageProvider extends StorageProvider {
  /// {@macro filesystem_storage_provider}
  FileSystemStorageProvider();
  String? _basePath;
  bool _isInitialized = false;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    final basePath = config['basePath'] as String?;
    if (basePath == null || basePath.isEmpty) {
      throw const AuthenticationException(
        'basePath is required for FileSystemStorageProvider',
      );
    }

    _basePath = basePath;

    // Ensure the base directory exists
    final directory = Directory(_basePath!);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    _isInitialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _isInitialized && _basePath != null;

  @override
  Future<String> createFile(
    String filePath,
    String content, {
    String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath!, filePath);
    final file = File(fullPath);

    // Check if file already exists
    if (await file.exists()) {
      throw FileNotFoundException('File already exists at path: $filePath');
    }

    // Ensure parent directory exists
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    await file.writeAsString(content);
    return fullPath;
  }

  @override
  Future<String?> getFile(String filePath) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      return null;
    }

    try {
      return await file.readAsString();
    } catch (e) {
      throw NetworkException('Failed to read file at $filePath: $e');
    }
  }

  @override
  Future<String> updateFile(
    String filePath,
    String content, {
    String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    await file.writeAsString(content);
    return fullPath;
  }

  @override
  Future<void> deleteFile(String filePath, {String? commitMessage}) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    await file.delete();
  }

  @override
  Future<List<String>> listFiles(String directoryPath) async {
    _ensureInitialized();

    final fullPath = path.join(_basePath!, directoryPath);
    final directory = Directory(fullPath);

    if (!await directory.exists()) {
      throw FileNotFoundException(
        'Directory not found at path: $directoryPath',
      );
    }

    final entities = await directory.list().toList();
    final relativePaths = <String>[];

    for (final entity in entities) {
      final relativePath = path.relative(entity.path, from: _basePath);
      relativePaths.add(relativePath);
    }

    return relativePaths;
  }

  @override
  Future<void> restore(String filePath, {String? versionId}) async {
    // For filesystem provider, restore is not meaningful without version control
    // This could be extended to support backup/snapshot functionality
    throw const UnsupportedOperationException(
      'Restore operation is not supported by FileSystemStorageProvider. '
      'Consider using OfflineGitStorageProvider for version control features.',
    );
  }

  @override
  bool get supportsSync => false;

  void _ensureInitialized() {
    if (!_isInitialized || _basePath == null) {
      throw const AuthenticationException(
        'Provider not initialized. Call init() first.',
      );
    }
  }
}
