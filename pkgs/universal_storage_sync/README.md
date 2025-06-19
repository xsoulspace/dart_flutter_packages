# Universal Storage Sync

A cross-platform Dart package providing a unified API for file storage operations with support for local filesystem, GitHub API, and Git-based version control.

## Features

- **Unified API**: Single interface for different storage providers
- **Cross-platform**: Works on desktop, mobile, and web platforms
- **Extensible**: Easy to add new storage providers
- **Type-safe Configuration**: Builder pattern for configurations with validation
- **Auto Provider Selection**: Smart recommendations based on requirements
- **Storage Factory**: Automatic provider creation from configurations
- **Version Control Ready**: Built-in support for Git-based storage
- **GitHub Integration**: Direct GitHub API integration for cloud storage
- **Offline-first**: Local operations with optional remote synchronization
- **Retry Logic**: Built-in retry mechanisms for network operations
- **Path Normalization**: Cross-platform path handling

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  universal_storage_sync: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Using StorageFactory (Recommended)

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Build configuration using type-safe builders
  final config = FileSystemConfig.builder()
      .basePath('/path/to/storage')
      .build();

  // Create service automatically using factory
  final storageService = await StorageFactory.create(config);

  // File operations are ready to use
  await storageService.saveFile('hello.txt', 'Hello, World!');
  final content = await storageService.readFile('hello.txt');
  print(content); // Output: Hello, World!
}
```

### Auto Provider Selection

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Define your requirements
  final requirements = const ProviderRequirements(
    needsVersionControl: true,
    needsOffline: true,
    hasGitCli: true,
  );

  // Get recommendation
  final recommendation = ProviderSelector.recommend(requirements);
  print('Recommended: ${recommendation.providerType}');
  print('Reason: ${recommendation.reason}');

  // Create service using recommendation
  final service = await StorageFactory.create(recommendation.configTemplate);
}
```

### Use Case-Based Selection

```dart
// Quick selection based on use case description
final requirements = ProviderSelector.fromUseCase('team collaboration project');
final recommendation = ProviderSelector.recommend(requirements);
final service = await StorageFactory.create(recommendation.configTemplate);
```

## Storage Providers

### 🏠 FileSystem Provider

Local file system storage with excellent performance.

```dart
final config = FileSystemConfig.builder()
    .basePath('/path/to/data')
    .databaseName('app_db') // For web platforms
    .build();

final service = await StorageFactory.createFileSystem(config);
```

**Best for:** Simple apps, offline-first, high performance local storage

### 🌐 GitHub API Provider

Cloud storage using GitHub repositories via REST API.

```dart
final config = GitHubApiConfig.builder()
    .authToken('ghp_your_token_here')
    .repositoryOwner('your-username')
    .repositoryName('your-repo')
    .branchName('main')
    .build();

final service = await StorageFactory.createGitHubApi(config);
```

**Best for:** Web apps, collaboration, cloud sync, no local Git required

### 🔄 Offline Git Provider

Local Git repository with optional remote synchronization.

```dart
final config = OfflineGitConfig.builder()
    .localPath('/path/to/repo')
    .branchName('main')
    .authorName('Your Name')
    .authorEmail('your@email.com')
    .remoteUrl('https://github.com/user/repo.git')
    .authentication()
    .sshKey('/path/to/ssh/key')
    .build();

final service = await StorageFactory.createOfflineGit(config);
```

**Best for:** Desktop apps, full Git features, offline capability, advanced workflows

## Provider Comparison

| Feature          | FileSystem | GitHub API   | Offline Git    |
| ---------------- | ---------- | ------------ | -------------- |
| Offline Support  | ✅ Full    | ❌ None      | ✅ Full        |
| Version Control  | ❌ None    | ✅ Git       | ✅ Full Git    |
| Collaboration    | ❌ None    | ✅ Excellent | ✅ With Remote |
| Setup Complexity | 🟢 Simple  | 🟡 Medium    | 🔴 Complex     |
| Web Support      | 🟡 Limited | ✅ Full      | ❌ None        |
| Performance      | 🟢 Fastest | 🟡 Network   | 🟢 Fast        |

## Advanced Features

### Configuration Builders

Type-safe configuration with validation:

```dart
// FileSystem with validation
final fsConfig = FileSystemConfig.builder()
    .basePath('/valid/path')  // Will validate path
    .build();

// GitHub with fluent API
final ghConfig = GitHubApiConfig.builder()
    .authToken('token')
    .repositoryOwner('owner')
    .repositoryName('repo')
    .branchName('develop')
    .build();

// Git with authentication methods
final gitConfig = OfflineGitConfig.builder()
    .localPath('/repo/path')
    .branchName('main')
    .remoteUrl('git@github.com:user/repo.git')
    .authentication()
    .sshKey('/path/to/key')  // or .httpsToken('token')
    .conflictResolution(ConflictResolutionStrategy.lastWriteWins)
    .build();
```

### Path Normalization

Cross-platform path handling:

```dart
final path = 'folder\\subfolder//file.txt';

// Normalize for different providers
final fsPath = PathNormalizer.normalize(path, ProviderType.filesystem);
final ghPath = PathNormalizer.normalize(path, ProviderType.github);
final gitPath = PathNormalizer.normalize(path, ProviderType.git);

// Validate paths
final isValid = PathNormalizer.isSafePath('docs/api.md', ProviderType.github);

// Join path segments
final joined = PathNormalizer.join(['docs', 'api', 'index.md'], ProviderType.github);
```

### Retry Operations

Built-in retry logic for robust operations:

```dart
// GitHub operations automatically retry on network errors
await RetryableOperation.github(() async {
  return await githubProvider.createFile('test.txt', 'content');
});

// Custom retry configuration
await RetryableOperation.execute(
  () => someNetworkOperation(),
  maxAttempts: 5,
  initialDelay: Duration(milliseconds: 1000),
  retryIf: (exception) => exception is NetworkException,
);
```

### Provider Selection API

Get all recommendations ranked by score:

```dart
final requirements = const ProviderRequirements(
  isWeb: true,
  needsRemoteSync: true,
  needsCollaboration: true,
);

final recommendations = ProviderSelector.getAllRecommendations(requirements);
for (final rec in recommendations) {
  print('${rec.providerType}: ${rec.score}/100 - ${rec.reason}');
}
```

## Migration Guide

### From Map-based to Builder Configurations

**Before (Stage 4):**

```dart
await storageService.initialize({
  'authToken': 'token',
  'repositoryOwner': 'owner',
  'repositoryName': 'repo',
});
```

**After (Stage 5):**

```dart
final config = GitHubApiConfig.builder()
    .authToken('token')
    .repositoryOwner('owner')
    .repositoryName('repo')
    .build();

final service = await StorageFactory.create(config);
```

### Benefits of Migration

- **Type Safety**: Catch configuration errors at compile time
- **Validation**: Builder validates required fields and formats
- **IDE Support**: Better autocomplete and documentation
- **Maintainability**: Clear, self-documenting configuration code

## API Reference

### StorageFactory

Factory for creating configured storage services:

```dart
// Auto-detect provider from config type
static Future<StorageService> create(StorageConfig config)

// Provider-specific factory methods
static Future<StorageService> createFileSystem(FileSystemConfig config)
static Future<StorageService> createGitHubApi(GitHubApiConfig config)
static Future<StorageService> createOfflineGit(OfflineGitConfig config)
```

### ProviderSelector

Smart provider recommendation:

```dart
// Get recommendation based on requirements
static ProviderRecommendation recommend(ProviderRequirements requirements)

// Get all recommendations ranked by score
static List<ProviderRecommendation> getAllRecommendations(ProviderRequirements requirements)

// Quick selection from use case description
static ProviderRequirements fromUseCase(String useCase)
```

### Configuration Builders

Type-safe configuration builders:

- `FileSystemConfig.builder()` - FileSystem configuration
- `GitHubApiConfig.builder()` - GitHub API configuration
- `OfflineGitConfig.builder()` - Offline Git configuration

### StorageService

Enhanced service API:

```dart
// New type-safe initialization (recommended)
Future<void> initializeWithConfig(StorageConfig config)

// Legacy map-based initialization (deprecated)
@Deprecated('Use initializeWithConfig instead')
Future<void> initialize(Map<String, dynamic> config)

// All existing file operations remain the same
Future<String> saveFile(String path, String content, {String? message})
Future<String?> readFile(String path)
Future<void> removeFile(String path, {String? message})
Future<List<String>> listDirectory(String path)
Future<void> restoreData(String path, {String? versionId})
Future<void> syncRemote({String? pullMergeStrategy, String? pushConflictStrategy})

// New utility methods
StorageProvider get provider
Future<bool> isAuthenticated()
```

## Error Handling

Enhanced exception hierarchy:

```dart
try {
  await storageService.readFile('file.txt');
} on FileNotFoundException catch (e) {
  print('File not found: $e');
} on NetworkException catch (e) {
  print('Network error: $e');
} on AuthenticationException catch (e) {
  print('Authentication failed: $e');
} on GitHubRateLimitException catch (e) {
  print('Rate limit exceeded: $e');
} on ConfigurationException catch (e) {
  print('Configuration error: $e');
}
```

## Examples

Check out the `example/` directory for comprehensive usage examples:

- `config_builder_usage.dart` - Configuration builder patterns
- `provider_factory_usage.dart` - StorageFactory and ProviderSelector usage
- `basic_usage.dart` - Simple file operations
- `github_api_usage.dart` - GitHub API integration
- `git_usage.dart` - Git-based storage

## Contributing

Contributions are welcome! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

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
