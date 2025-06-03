# Universal Storage Sync

A cross-platform Dart package providing a unified API for file storage operations with support for local filesystem and Git-based version control.

## Features

- **Unified API**: Single interface for different storage providers
- **Cross-platform**: Works on desktop, mobile, and web platforms
- **Extensible**: Easy to add new storage providers
- **Type-safe Configuration**: Structured configuration classes for each provider
- **Version Control Ready**: Built-in support for Git-based storage (coming in Stage 2)
- **Offline-first**: Local operations with optional remote synchronization

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  universal_storage_sync: ^0.1.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Basic File Operations

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'dart:io';

Future<void> main() async {
  // Create a storage service with filesystem provider
  final provider = FileSystemStorageProvider();
  final storageService = StorageService(provider);

  // Initialize with a base path
  await storageService.initialize({
    'basePath': '/path/to/your/storage/directory',
  });

  // Save a file
  await storageService.saveFile('hello.txt', 'Hello, World!');

  // Read a file
  final content = await storageService.readFile('hello.txt');
  print(content); // Output: Hello, World!

  // List files in a directory
  final files = await storageService.listDirectory('.');
  print(files); // Output: [hello.txt]

  // Delete a file
  await storageService.removeFile('hello.txt');
}
```

### Using Typed Configuration

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Use typed configuration for better type safety
  final config = FileSystemConfig(basePath: '/path/to/storage');
  final provider = FileSystemStorageProvider();
  final storageService = StorageService(provider);

  await storageService.initialize(config.toMap());

  // Your file operations here...
}
```

### Git-based Storage with Version Control

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Create a Git-based storage service
  final provider = OfflineGitStorageProvider();
  final storageService = StorageService(provider);

  // Initialize with Git configuration
  await storageService.initialize({
    'localPath': '/path/to/git/repository',
    'branchName': 'main',
    'authorName': 'Your Name',
    'authorEmail': 'your.email@example.com',
  });

  // Save a file with automatic Git commit
  await storageService.saveFile(
    'README.md',
    '# My Project\n\nThis is version controlled!',
    message: 'docs: Add initial README',
  );

  // Update the file with another commit
  await storageService.saveFile(
    'README.md',
    '# My Project\n\nThis is version controlled!\n\n## Features\n- Git integration',
    message: 'docs: Add features section',
  );

  // Restore file to previous version
  await storageService.restoreData('README.md');

  // The file is now restored to its previous state
  final content = await storageService.readFile('README.md');
  print(content); // Original content without features section
}
```

## Available Storage Providers

### FileSystemStorageProvider

Uses the local file system for storage operations.

**Configuration:**

- `basePath` (required): Base directory path for file operations
- `databaseName` (optional): Database name for web platforms using IndexedDB

**Features:**

- ✅ Create, read, update, delete files
- ✅ List directory contents
- ✅ Nested directory creation
- ❌ Version control
- ❌ Remote synchronization

### OfflineGitStorageProvider

Uses a local Git repository with optional remote synchronization.

**Configuration:**

- `localPath` (required): Path to the local Git repository
- `branchName` (required): Primary local and remote branch name
- `authorName` (optional): Author name for Git commits
- `authorEmail` (optional): Author email for Git commits

**Features:**

- ✅ All filesystem operations
- ✅ Version control with Git
- ✅ Automatic Git commits for all operations
- ✅ File restoration to previous versions
- ✅ Git-aware file listing (excludes .git directory)
- ⏳ Remote synchronization (Stage 3)
- ⏳ Conflict resolution strategies (Stage 3)

## API Reference

### StorageService

The main entry point for all storage operations.

#### Methods

- `initialize(Map<String, dynamic> config)` - Initialize the storage provider
- `saveFile(String path, String content, {String? message})` - Save (create or update) a file
- `readFile(String path)` - Read file content, returns `null` if not found
- `removeFile(String path, {String? message})` - Delete a file
- `listDirectory(String path)` - List files and directories
- `restoreData(String path, {String? versionId})` - Restore file to previous version
- `syncRemote({String? pullMergeStrategy, String? pushConflictStrategy})` - Sync with remote storage

### StorageProvider

Abstract base class for all storage providers.

### Configuration Classes

- `FileSystemConfig` - Configuration for filesystem storage
- `OfflineGitConfig` - Configuration for Git-based storage (Stage 2)
- `GitHubApiConfig` - Configuration for GitHub API storage (Stage 5)

## Error Handling

The package provides specific exception types for different error scenarios:

```dart
try {
  await storageService.readFile('nonexistent.txt');
} on FileNotFoundException catch (e) {
  print('File not found: $e');
} on NetworkException catch (e) {
  print('Network error: $e');
} on AuthenticationException catch (e) {
  print('Authentication failed: $e');
}
```

### Exception Types

- `StorageException` - Base exception for all storage errors
- `FileNotFoundException` - File or directory not found
- `NetworkException` - Network-related errors
- `AuthenticationException` - Authentication or configuration errors
- `GitConflictException` - Git operation conflicts (Stage 2)
- `SyncConflictException` - Synchronization conflicts (Stage 3)
- `UnsupportedOperationException` - Operation not supported by provider

## Development Roadmap

### ✅ Stage 1: Core Abstractions & FileSystem Provider

- Core interfaces and service class
- FileSystem storage provider
- Basic tests and examples
- Configuration system

### ✅ Stage 2: OfflineGitStorageProvider - Local Operations

- Local Git repository operations
- File versioning and history
- Git-based file operations
- Automatic commit generation
- File restoration capabilities

### 📋 Stage 3: OfflineGitStorageProvider - Remote Sync (Planned)

- Remote Git synchronization
- Conflict resolution strategies
- "Client is always right" merge strategies

### 📋 Stage 4: API-Assisted Features (Planned)

- GitHub API integration for repository management
- Enhanced remote operations

### 📋 Stage 5: Lightweight API-Only Providers (Planned)

- Direct GitHub API provider
- Other cloud storage providers

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Examples

Check out the `example/` directory for more comprehensive examples:

- `basic_usage.dart` - Basic file operations and error handling
- More examples coming with each development stage

## Platform Support

| Platform | FileSystemStorageProvider | OfflineGitStorageProvider |
| -------- | ------------------------- | ------------------------- |
| Desktop  | ✅                        | 🚧 (Stage 2)              |
| Mobile   | ✅                        | 🚧 (Stage 2)              |
| Web      | ✅ (IndexedDB)            | ❌                        |

## Requirements

- Dart SDK: `>=3.0.0 <4.0.0`
- For Git operations (Stage 2+): Git CLI installed and in PATH

---

For more information, visit our [GitHub repository](https://github.com/xsoulspace/universal_storage_sync).
