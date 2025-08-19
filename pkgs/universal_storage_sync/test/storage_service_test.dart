import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

class _FakeStorageProvider extends StorageProvider {
  final Map<String, String> _files = {};
  var _initialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const AuthenticationException(
        'Provider not initialized. Call init() first.',
      );
    }
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (_files.containsKey(path)) {
      throw FileAlreadyExistsException('File already exists at path: $path');
    }
    _files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    return _files[path];
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (!_files.containsKey(path)) {
      throw FileNotFoundException('File not found at path: $path');
    }
    _files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (!_files.containsKey(path)) {
      throw FileNotFoundException('File not found at path: $path');
    }
    _files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final now = DateTime.now();

    final entries = <String, FileEntry>{};
    for (final fullPath in _files.keys) {
      final relative = directoryPath == '.' || directoryPath.isEmpty
          ? fullPath
          : fullPath.startsWith(
              '${directoryPath.replaceAll(RegExp(r'\./'), '')}/',
            )
          ? fullPath.substring(
              directoryPath.length + (directoryPath.endsWith('/') ? 0 : 1),
            )
          : null;
      if (relative == null) continue;

      final parts = relative.split('/');
      if (parts.length == 1) {
        entries[parts[0]] = FileEntry(
          name: parts[0],
          isDirectory: false,
          size: _files[fullPath]!.length,
          modifiedAt: now,
        );
      } else if (parts.isNotEmpty) {
        final dirName = parts.first;
        entries.putIfAbsent(
          dirName,
          () => FileEntry(name: dirName, isDirectory: true, modifiedAt: now),
        );
      }
    }

    return entries.values.toList();
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {
    _ensureInitialized();
    throw const UnsupportedOperationException('Restore not supported in fake');
  }

  @override
  bool get supportsSync => false;
}

void main() {
  group('StorageService with FakeStorageProvider', () {
    late StorageService storageService;
    late _FakeStorageProvider provider;

    setUp(() async {
      provider = _FakeStorageProvider();
      storageService = StorageService(provider);

      final tempDirectory = await Directory.systemTemp.createTemp(
        'storage_test_',
      );
      final config = FileSystemConfig(basePath: tempDirectory.path);
      await storageService.initializeWithConfig(config);
    });

    test('should save and read a file', () async {
      const filePath = 'test.txt';
      const content = 'Hello, World!';

      final savedResult = await storageService.saveFile(filePath, content);
      expect(savedResult.path, contains(filePath));

      final readContent = await storageService.readFile(filePath);
      expect(readContent, equals(content));
    });

    test('should update an existing file', () async {
      const filePath = 'test.txt';
      const initialContent = 'Initial content';
      const updatedContent = 'Updated content';

      await storageService.saveFile(filePath, initialContent);
      await storageService.saveFile(filePath, updatedContent);

      final readContent = await storageService.readFile(filePath);
      expect(readContent, equals(updatedContent));
    });

    test('should remove a file', () async {
      const filePath = 'test.txt';
      const content = 'Content to be deleted';

      await storageService.saveFile(filePath, content);

      final contentBeforeDelete = await storageService.readFile(filePath);
      expect(contentBeforeDelete, equals(content));

      await storageService.removeFile(filePath);

      final contentAfterDelete = await storageService.readFile(filePath);
      expect(contentAfterDelete, isNull);
    });

    test('should list files in directory', () async {
      await storageService.saveFile('file1.txt', 'Content 1');
      await storageService.saveFile('file2.txt', 'Content 2');
      await storageService.saveFile('subdir/file3.txt', 'Content 3');

      final entries = await storageService.listDirectory('.');
      final names = entries.map((final e) => e.name).toList();

      expect(names, contains('file1.txt'));
      expect(names, contains('file2.txt'));
      expect(names, contains('subdir'));
    });

    test('should return null for non-existent file', () async {
      final content = await storageService.readFile('non_existent.txt');
      expect(content, isNull);
    });

    test('should throw exception when removing non-existent file', () {
      expect(
        () => storageService.removeFile('non_existent.txt'),
        throwsA(isA<FileNotFoundException>()),
      );
    });

    test('should handle nested directory creation', () async {
      const filePath = 'deep/nested/directory/file.txt';
      const content = 'Nested content';

      await storageService.saveFile(filePath, content);

      final readContent = await storageService.readFile(filePath);
      expect(readContent, equals(content));
    });
  });

  group('StorageService sync operations', () {
    test('should handle sync gracefully for non-sync providers', () async {
      final provider = _FakeStorageProvider();
      final storageService = StorageService(provider);

      final tempDirectory = await Directory.systemTemp.createTemp(
        'storage_test_',
      );
      final config = FileSystemConfig(basePath: tempDirectory.path);
      await storageService.initializeWithConfig(config);

      await storageService.syncRemote();

      await tempDirectory.delete(recursive: true);
    });
  });
}
