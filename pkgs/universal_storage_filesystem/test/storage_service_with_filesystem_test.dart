import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';

void main() {
  group('StorageService with FileSystemStorageProvider', () {
    late StorageService storageService;
    late String tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      final tempDirectory = await Directory.systemTemp.createTemp(
        'storage_test_',
      );
      tempDir = tempDirectory.path;

      final provider = FileSystemStorageProvider();
      storageService = StorageService(provider);

      final config = FileSystemConfig(basePath: tempDir);
      await storageService.initializeWithConfig(config);
    });

    tearDown(() async {
      // Clean up temporary directory
      final directory = Directory(tempDir);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('should save and read a file', () async {
      const filePath = 'test.txt';
      const content = 'Hello, World!';

      // Save file
      final savedResult = await storageService.saveFile(filePath, content);
      expect(savedResult.path, contains(filePath));

      // Read file
      final readContent = await storageService.readFile(filePath);
      expect(readContent, equals(content));
    });

    test('should update an existing file', () async {
      const filePath = 'test.txt';
      const initialContent = 'Initial content';
      const updatedContent = 'Updated content';

      // Create initial file
      await storageService.saveFile(filePath, initialContent);

      // Update file
      await storageService.saveFile(filePath, updatedContent);

      // Verify updated content
      final readContent = await storageService.readFile(filePath);
      expect(readContent, equals(updatedContent));
    });

    test('should remove a file', () async {
      const filePath = 'test.txt';
      const content = 'Content to be deleted';

      // Create file
      await storageService.saveFile(filePath, content);

      // Verify file exists
      final contentBeforeDelete = await storageService.readFile(filePath);
      expect(contentBeforeDelete, equals(content));

      // Remove file
      await storageService.removeFile(filePath);

      // Verify file is gone
      final contentAfterDelete = await storageService.readFile(filePath);
      expect(contentAfterDelete, isNull);
    });

    test('should list files in directory', () async {
      // Create some test files
      await storageService.saveFile('file1.txt', 'Content 1');
      await storageService.saveFile('file2.txt', 'Content 2');
      await storageService.saveFile('subdir/file3.txt', 'Content 3');

      // List files in root directory
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
}


