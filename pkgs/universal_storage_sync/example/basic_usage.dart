import 'dart:io';

import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Example 1: Using FileSystemStorageProvider with raw config
  print('=== Example 1: FileSystem Storage with Raw Config ===');
  await fileSystemExample();

  print('\n=== Example 2: FileSystem Storage with Typed Config ===');
  await fileSystemTypedConfigExample();

  print('\n=== Example 3: Demonstrating Error Handling ===');
  await errorHandlingExample();
}

Future<void> fileSystemExample() async {
  // Create a temporary directory for this example
  final tempDir = await Directory.systemTemp.createTemp('storage_example_');

  try {
    // Initialize the storage service with FileSystemStorageProvider
    final provider = FileSystemStorageProvider();
    final storageService = StorageService(provider);

    // Initialize with configuration
    await storageService.initialize({
      'basePath': tempDir.path,
    });

    // Create and save a file
    const content = 'Hello, Universal Storage Sync!';
    final savedPath = await storageService.saveFile('hello.txt', content);
    print('File saved to: $savedPath');

    // Read the file back
    final readContent = await storageService.readFile('hello.txt');
    print('File content: $readContent');

    // Update the file
    const updatedContent = 'Hello, Updated Content!';
    await storageService.saveFile('hello.txt', updatedContent);
    print('File updated');

    // Read updated content
    final updatedReadContent = await storageService.readFile('hello.txt');
    print('Updated content: $updatedReadContent');

    // Create a file in a subdirectory
    await storageService.saveFile(
        'docs/readme.md', '# My Project\n\nThis is a readme file.');
    print('Created file in subdirectory');

    // List files in the root directory
    final files = await storageService.listDirectory('.');
    print('Files in root directory: $files');

    // List files in the docs directory
    final docsFiles = await storageService.listDirectory('docs');
    print('Files in docs directory: $docsFiles');

    // Delete a file
    await storageService.removeFile('hello.txt');
    print('File deleted');

    // Try to read deleted file
    final deletedContent = await storageService.readFile('hello.txt');
    print('Deleted file content (should be null): $deletedContent');
  } finally {
    // Clean up
    await tempDir.delete(recursive: true);
    print('Cleaned up temporary directory');
  }
}

Future<void> fileSystemTypedConfigExample() async {
  // Create a temporary directory for this example
  final tempDir =
      await Directory.systemTemp.createTemp('storage_typed_example_');

  try {
    // Initialize using typed configuration
    final config = FileSystemConfig(basePath: tempDir.path);
    final provider = FileSystemStorageProvider();
    final storageService = StorageService(provider);

    await storageService.initialize(config.toMap());

    // Save some configuration data
    const configData = '''
{
  "appName": "My App",
  "version": "1.0.0",
  "settings": {
    "theme": "dark",
    "language": "en"
  }
}
''';

    await storageService.saveFile('config/app.json', configData);
    print('Configuration saved');

    // Read and display the configuration
    final savedConfig = await storageService.readFile('config/app.json');
    print('Saved configuration:\n$savedConfig');
  } finally {
    // Clean up
    await tempDir.delete(recursive: true);
    print('Cleaned up temporary directory');
  }
}

Future<void> errorHandlingExample() async {
  final tempDir =
      await Directory.systemTemp.createTemp('storage_error_example_');

  try {
    final provider = FileSystemStorageProvider();
    final storageService = StorageService(provider);

    await storageService.initialize({'basePath': tempDir.path});

    // Try to read a non-existent file
    final nonExistentContent =
        await storageService.readFile('does_not_exist.txt');
    print('Non-existent file content: $nonExistentContent');

    // Try to delete a non-existent file (this will throw an exception)
    try {
      await storageService.removeFile('does_not_exist.txt');
    } on FileNotFoundException catch (e) {
      print('Caught expected exception: $e');
    }

    // Try to sync with a provider that doesn't support sync
    await storageService.syncRemote();
    print('Sync completed (or gracefully handled)');

    // Demonstrate OfflineGitStorageProvider placeholder
    try {
      final gitProvider = OfflineGitStorageProvider();
      await gitProvider.init({});
    } on UnsupportedOperationException catch (e) {
      print('Git provider not yet implemented: $e');
    }
  } finally {
    // Clean up
    await tempDir.delete(recursive: true);
    print('Cleaned up temporary directory');
  }
}
