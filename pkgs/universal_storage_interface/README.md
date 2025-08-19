# universal_storage_interface

Core contracts and models for Universal Storage providers. This package defines the foundational interfaces, models, and contracts that all storage providers must implement.

## Features

- **StorageProvider Interface**: Abstract contract for all storage implementations
- **StorageService**: Main service class providing unified API across providers
- **Configuration Models**: Type-safe config classes for different storage backends
- **Exception Hierarchy**: Comprehensive error handling with specific exception types
- **Version Control Models**: Shared models for Git-based operations

## Installation

```yaml
dependencies:
  universal_storage_interface: ^0.1.0
```

## Core Components

### StorageProvider Interface

The main contract that all storage providers must implement:

```dart
abstract class StorageProvider {
  Future<void> initialize(StorageConfig config);
  Future<FileOperationResult> saveFile(String path, String content, {String? message});
  Future<String?> readFile(String path);
  Future<FileOperationResult> removeFile(String path, {String? message});
  Future<List<FileEntry>> listDirectory(String path);
  Future<void> restoreData(String path, {String? versionId});
  Future<void> syncRemote({String? pullMergeStrategy, String? pushConflictStrategy});
  Future<bool> isAuthenticated();
}
```

### Configuration Classes

Type-safe configuration for different storage backends:

```dart
// Base configuration
abstract class StorageConfig {
  final String? name;
  final Map<String, dynamic>? metadata;

  const StorageConfig({this.name, this.metadata});
}

// FileSystem configuration
class FileSystemConfig extends StorageConfig {
  final String basePath;

  const FileSystemConfig({required this.basePath, super.name});
}

// GitHub API configuration
class GitHubApiConfig extends StorageConfig {
  final String authToken;
  final VcRepositoryOwner repositoryOwner;
  final VcRepositoryName repositoryName;
  final VcBranchName branchName;

  const GitHubApiConfig({
    required this.authToken,
    required this.repositoryOwner,
    required this.repositoryName,
    required this.branchName,
    super.name,
  });
}

// Offline Git configuration
class OfflineGitConfig extends StorageConfig {
  final String localPath;
  final VcBranchName branchName;
  final String authorName;
  final String authorEmail;
  final VcUrl? remoteUrl;
  final String? sshKeyPath;
  final String? httpsToken;

  const OfflineGitConfig({
    required this.localPath,
    required this.branchName,
    required this.authorName,
    required this.authorEmail,
    this.remoteUrl,
    this.sshKeyPath,
    this.httpsToken,
    super.name,
  });
}
```

### Core Models

#### FileEntry

Represents a file or directory in storage:

```dart
class FileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? lastModified;
  final String? versionId;

  const FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.lastModified,
    this.versionId,
  });
}
```

#### FileOperationResult

Result of file operations with metadata:

```dart
class FileOperationResult {
  final bool success;
  final String? message;
  final String? versionId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const FileOperationResult({
    required this.success,
    this.message,
    this.versionId,
    required this.timestamp,
    this.metadata,
  });
}
```

#### Version Control Models

```dart
class VcRepositoryOwner {
  final String value;
  const VcRepositoryOwner(this.value);
}

class VcRepositoryName {
  final String value;
  const VcRepositoryName(this.value);
}

class VcBranchName {
  final String value;
  const VcBranchName(this.value);

  static const main = VcBranchName('main');
  static const master = VcBranchName('master');
}

class VcUrl {
  final String value;
  const VcUrl(this.value);
}
```

### Exception Hierarchy

Comprehensive error handling with specific exception types:

```dart
// Base storage exception
abstract class StorageException implements Exception {
  final String message;
  final String? path;
  final dynamic originalError;

  const StorageException(this.message, {this.path, this.originalError});
}

// Specific exception types
class FileNotFoundException extends StorageException {
  const FileNotFoundException(String path) : super('File not found: $path', path: path);
}

class AuthenticationException extends StorageException {
  const AuthenticationException(String message) : super(message);
}

class NetworkException extends StorageException {
  const NetworkException(String message, {dynamic originalError})
    : super(message, originalError: originalError);
}

class GitConflictException extends StorageException {
  const GitConflictException(String message, {String? path})
    : super(message, path: path);
}

class ConfigurationException extends StorageException {
  const ConfigurationException(String message) : super(message);
}

class UnsupportedOperationException extends StorageException {
  const UnsupportedOperationException(String operation, {String? path})
    : super('Operation not supported: $operation', path: path);
}
```

## Usage

### Basic Provider Implementation

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';

class MyCustomStorageProvider implements StorageProvider {
  @override
  Future<void> initialize(StorageConfig config) async {
    // Initialize your storage backend
  }

  @override
  Future<FileOperationResult> saveFile(String path, String content, {String? message}) async {
    // Implement file saving logic
    return FileOperationResult(
      success: true,
      message: 'File saved successfully',
      timestamp: DateTime.now(),
    );
  }

  // Implement other required methods...
}
```

### Using with StorageService

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() async {
  final provider = MyCustomStorageProvider();
  final service = StorageService(provider);

  await service.initializeWithConfig(MyCustomConfig());

  // Use the service
  await service.saveFile('test.txt', 'Hello World');
  final content = await service.readFile('test.txt');
}
```

## Provider Implementations

This package is used by concrete storage providers:

- **universal_storage_filesystem**: Local filesystem storage
- **universal_storage_github_api**: GitHub API-based storage
- **universal_storage_git_offline**: Local Git repository storage

## Requirements

- Dart SDK: `>=3.8.1 <4.0.0`

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions welcome! Please read the Contributing Guide before submitting PRs.

## Related Packages

- [universal_storage_sync](https://github.com/xsoulspace/universal_storage_sync) - Main package with provider implementations
- [universal_storage_filesystem](https://github.com/xsoulspace/universal_storage_sync/tree/main/pkgs/universal_storage_filesystem) - Filesystem provider
- [universal_storage_github_api](https://github.com/xsoulspace/universal_storage_sync/tree/main/pkgs/universal_storage_github_api) - GitHub API provider
- [universal_storage_git_offline](https://github.com/xsoulspace/universal_storage_sync/tree/main/pkgs/universal_storage_git_offline) - Offline Git provider
