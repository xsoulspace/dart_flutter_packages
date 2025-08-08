// ignore_for_file: avoid_print, avoid_catches_without_on_clauses

import 'dart:io';

import 'package:universal_storage_sync/universal_storage_sync.dart';

/// Example demonstrating Git-specific features of OfflineGitStorageProvider
Future<void> main() async {
  print('🚀 Universal Storage Sync - Git Usage Example\n');

  // Create a temporary directory for this example
  final tempDir = await Directory.systemTemp.createTemp('git_example_');
  final gitRepoPath = tempDir.path;

  try {
    await demonstrateGitFeatures(gitRepoPath);
  } finally {
    // Clean up
    await tempDir.delete(recursive: true);
    print('\n🧹 Cleaned up temporary directory');
  }
}

Future<void> demonstrateGitFeatures(final String repoPath) async {
  print('📁 Repository path: $repoPath\n');

  // 1. Repository Initialization
  print('1️⃣ Repository Initialization');
  print('=' * 40);

  final provider = OfflineGitStorageProvider();
  final storageService = StorageService(provider);

  final offlineGitConfig = OfflineGitConfig(
    localPath: repoPath,
    authorName: 'Your Name',
    authorEmail: 'your.email@example.com',
  );
  await storageService.initializeWithConfig(offlineGitConfig);
  print('✅ Git repository initialized successfully');
  print('📂 Branch: main');
  print('👤 Author: Demo User <demo@example.com>\n');

  // 2. File Operations with Commit Messages
  print('2️⃣ File Operations with Git Commits');
  print('=' * 40);

  // Create a file
  const readmePath = 'README.md';
  const readmeContent = '''
# My Project

This is a sample project demonstrating Git-based storage.

## Features
- Version control
- Automatic commits
- File restoration
''';

  final createResult = await storageService.saveFile(
    readmePath,
    readmeContent,
    message: 'docs: Add initial README',
  );
  print('✅ Created README.md');
  print('📝 Commit hash: ${createResult.revisionId.substring(0, 8)}...\n');

  // Create another file
  const configPath = 'config.yaml';
  const configContent = '''
app:
  name: "My App"
  version: "1.0.0"
  debug: true
''';

  await storageService.saveFile(
    configPath,
    configContent,
    message: 'feat: Add application configuration',
  );
  print('✅ Created config.yaml\n');

  // Update the README
  const updatedReadmeContent = '''
# My Project

This is a sample project demonstrating Git-based storage.

## Features
- Version control
- Automatic commits
- File restoration
- Configuration management

## Getting Started
1. Clone the repository
2. Configure your settings
3. Run the application
''';

  final updateResult = await storageService.saveFile(
    readmePath,
    updatedReadmeContent,
    message: 'docs: Update README with getting started section',
  );
  print('✅ Updated README.md');
  print('📝 Commit hash: ${updateResult.revisionId.substring(0, 8)}...\n');

  // 3. Version Control Features
  print('3️⃣ Version Control Features');
  print('=' * 40);

  // List files
  final entries = await storageService.listDirectory('.');
  print('📋 Files in repository:');
  for (final entry in entries) {
    if (!entry.name.startsWith('.')) {
      print('   - ${entry.name}${entry.isDirectory ? '/' : ''}');
    }
  }
  print('');

  // Demonstrate file restoration
  print('🔄 Demonstrating file restoration...');

  // Manually modify the README (simulating external change)
  final readmeFile = File('$repoPath/$readmePath');
  await readmeFile.writeAsString(
    '# Corrupted Content\n\nThis file was modified externally.',
  );

  print('⚠️  README.md was modified externally');
  final corruptedContent = await storageService.readFile(readmePath);
  print('📄 Current content preview: ${corruptedContent?.substring(0, 30)}...');

  // Restore the file
  await storageService.restoreData(readmePath);
  print('✅ Restored README.md from Git history');

  final restoredContent = await storageService.readFile(readmePath);
  print(
    '📄 Restored content preview: ${restoredContent?.substring(0, 50)}...\n',
  );

  // 4. Advanced Git Operations
  print('4️⃣ Advanced Git Operations');
  print('=' * 40);

  // Create a subdirectory with files
  await storageService.saveFile('src/main.dart', '''
void main() {
  print('Hello, Git World!');
}
''', message: 'feat: Add main application entry point');

  await storageService.saveFile('src/utils/helpers.dart', '''
class StringHelper {
  static String capitalize(String text) {
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }
}
''', message: 'feat: Add string helper utilities');

  print('✅ Created source files in subdirectories');

  // List all files recursively
  final allFiles = await _listAllFiles(storageService, '.');
  print('📋 All files in repository:');
  for (final file in allFiles) {
    print('   - $file');
  }
  print('');

  // 5. Error Handling Examples
  print('5️⃣ Error Handling Examples');
  print('=' * 40);

  // Try to create a duplicate file
  try {
    await provider.createFile(readmePath, 'duplicate content');
  } catch (e) {
    print('❌ Expected error for duplicate file: ${e.runtimeType}');
  }

  // Try to update a non-existent file
  try {
    await provider.updateFile('non_existent.txt', 'content');
  } catch (e) {
    print('❌ Expected error for non-existent file: ${e.runtimeType}');
  }

  // Try to restore with invalid version
  try {
    await provider.restore(readmePath, versionId: 'invalid_hash');
  } catch (e) {
    print('❌ Expected error for invalid version: ${e.runtimeType}');
  }

  print('');

  // 6. Sync Support Information
  print('6️⃣ Sync Support Information');
  print('=' * 40);

  print(
    '🔄 Sync support: ${provider.supportsSync ? "✅ Enabled" : "❌ Disabled"}',
  );
  print('📡 Remote sync will be available in Stage 3');

  try {
    await storageService.syncRemote();
  } catch (e) {
    print('⏳ Sync not yet implemented: ${e.runtimeType}');
  }

  print('\n🎉 Git usage demonstration completed successfully!');
  print('💡 This example showed:');
  print('   - Repository initialization and configuration');
  print('   - File operations with meaningful commit messages');
  print('   - Version control and file restoration');
  print('   - Directory operations and file listing');
  print('   - Error handling for various scenarios');
  print('   - Sync support status');
}

/// Helper function to recursively list all files
Future<List<String>> _listAllFiles(
  final StorageService service,
  final String dir,
) async {
  final allFiles = <String>[];
  final items = await service.listDirectory(dir);

  for (final item in items) {
    final name = item.name;
    final itemPath = dir == '.' ? name : '$dir/$name';

    // Skip hidden files and directories
    if (name.startsWith('.')) continue;

    try {
      // Try to list as directory
      final subItems = await service.listDirectory(itemPath);
      if (subItems.isEmpty && !item.isDirectory) {
        allFiles.add(itemPath);
        continue;
      }

      // If successful, it's a directory - recurse
      final subFiles = await _listAllFiles(service, itemPath);
      allFiles.addAll(subFiles);
    } catch (e) {
      // If it fails, it's a file
      allFiles.add(itemPath);
    }
  }

  return allFiles;
}
