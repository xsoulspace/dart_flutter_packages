# Universal Storage Sync

A cross-platform Dart package providing a unified API for file storage operations with support for local filesystem, GitHub API, and Git-based version control.

## Features

- **Unified API**: Single interface for different storage providers through `StorageService`
- **Cross-platform**: Works on desktop, mobile, and web platforms
- **Multiple Providers**: FileSystem, GitHub API, and Offline Git storage
- **Type-safe Configuration**: Strongly typed configuration classes with validation
- **Smart Provider Selection**: Automatic recommendations based on requirements
- **Version Control Ready**: Built-in support for Git-based storage with commit messages
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

### Basic Usage with FileSystem Provider

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Create and configure the storage service
  final provider = FileSystemStorageProvider();
  final storageService = StorageService(provider);

  // Initialize with configuration
  final config = FileSystemConfig(basePath: '/path/to/storage');
  await storageService.initializeWithConfig(config);

  // File operations
  await storageService.saveFile('hello.txt', 'Hello, World!');
  final content = await storageService.readFile('hello.txt');
  print(content); // Output: Hello, World!

  // List files
  final files = await storageService.listDirectory('.');
  print('Files: $files');

  // Delete file
  await storageService.removeFile('hello.txt');
}
```

### Using StorageFactory (Recommended)

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  // Create service using factory - automatically initialized
  final config = FileSystemConfig(basePath: '/path/to/storage');
  final storageService = await StorageFactory.create(config);

  // Ready to use immediately
  await storageService.saveFile('hello.txt', 'Hello, World!');
  final content = await storageService.readFile('hello.txt');
  print(content);
}
```

## Real-World Example: Todo App

Here's how the library is used in a real Flutter todo application:

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';

class TodoAppState extends ChangeNotifier {
  StorageService? _storageService;
  List<Todo> todos = [];
  bool busy = false;
  String? error;

  /// Initialize storage for a workspace
  Future<void> setWorkspacePath(String pathValue) async {
    busy = true;
    notifyListeners();

    try {
      // Validate directory
      final directory = Directory(pathValue);
      if (!await directory.exists()) {
        throw Exception('Directory does not exist: $pathValue');
      }

      // Initialize storage
      final config = FileSystemConfig(basePath: pathValue);
      _storageService = StorageService(FileSystemStorageProvider());
      await _storageService!.initializeWithConfig(config);

      // Load existing todos
      await loadTodos();
      error = null;
    } catch (e) {
      error = 'Failed to set workspace: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Load all todos from storage
  Future<void> loadTodos() async {
    if (_storageService == null) return;

    try {
      final fileList = await _storageService!.listDirectory('todos');
      final loadedTodos = <Todo>[];

      for (final fileName in fileList) {
        if (fileName.endsWith('.yaml')) {
          final content = await _storageService!.readFile(fileName);
          if (content != null) {
            final todoData = loadYaml(content) as Map;
            loadedTodos.add(Todo.fromJson(Map<String, dynamic>.from(todoData)));
          }
        }
      }

      todos = loadedTodos;
      notifyListeners();
    } catch (e) {
      error = 'Failed to load todos: $e';
      notifyListeners();
    }
  }

  /// Save a todo with version control message
  Future<void> saveTodo(Todo todo) async {
    if (_storageService == null) return;

    try {
      final fileName = 'todos/${todo.id}.yaml';
      final yamlContent = todoToYaml(todo);

      // Save with commit message for version control providers
      await _storageService!.saveFile(
        fileName,
        yamlContent,
        message: 'Save todo: ${todo.title}',
      );

      // Update local list
      final existingIndex = todos.indexWhere((t) => t.id == todo.id);
      if (existingIndex >= 0) {
        todos[existingIndex] = todo;
      } else {
        todos.add(todo);
      }
      notifyListeners();
    } catch (e) {
      error = 'Failed to save todo: $e';
      notifyListeners();
    }
  }

  /// Delete a todo
  Future<void> deleteTodo(String todoId) async {
    if (_storageService == null) return;

    try {
      final fileName = 'todos/$todoId.yaml';
      await _storageService!.removeFile(
        fileName,
        message: 'Delete todo: $todoId',
      );

      todos.removeWhere((todo) => todo.id == todoId);
      notifyListeners();
    } catch (e) {
      error = 'Failed to delete todo: $e';
      notifyListeners();
    }
  }
}
```

## Storage Providers

### 🏠 FileSystem Provider

Local file system storage with excellent performance.

```dart
final config = FileSystemConfig(
  basePath: '/path/to/data',
  databaseName: 'app_db', // For web platforms
);

final service = await StorageFactory.createFileSystem(config);
```

**Best for:** Desktop/mobile apps, offline-first, high performance local storage

**Features:**

- Fast local file operations
- Cross-platform path handling
- Web support via IndexedDB
- No external dependencies

### 🌐 GitHub API Provider

Cloud storage using GitHub repositories via REST API.

```dart
final config = GitHubApiConfig(
  authToken: 'ghp_your_token_here',
  repositoryOwner: 'your-username',
  repositoryName: 'your-repo',
  branchName: 'main',
);

final service = await StorageFactory.createGitHubApi(config);
```

**Best for:** Web apps, collaboration, cloud sync, no local Git required

**Features:**

- Full GitHub integration
- Automatic commit messages
- Branch management
- Collaboration features
- No local Git CLI required

### 🔄 Offline Git Provider

Local Git repository with optional remote synchronization.

```dart
final config = OfflineGitConfig(
  localPath: '/path/to/repo',
  branchName: 'main',
  authorName: 'Your Name',
  authorEmail: 'your@email.com',
  remoteUrl: 'https://github.com/user/repo.git',
  sshKeyPath: '/path/to/ssh/key',
);

final service = await StorageFactory.createOfflineGit(config);
```

**Best for:** Desktop apps, full Git features, offline capability, advanced workflows

**Features:**

- Full Git version control
- Offline capability
- Remote synchronization
- SSH/HTTPS authentication
- Advanced merge strategies

## Provider Comparison

| Feature          | FileSystem | GitHub API   | Offline Git    |
| ---------------- | ---------- | ------------ | -------------- |
| Offline Support  | ✅ Full    | ❌ None      | ✅ Full        |
| Version Control  | ❌ None    | ✅ Git       | ✅ Full Git    |
| Collaboration    | ❌ None    | ✅ Excellent | ✅ With Remote |
| Setup Complexity | 🟢 Simple  | 🟡 Medium    | 🔴 Complex     |
| Web Support      | 🟡 Limited | ✅ Full      | ❌ None        |
| Performance      | 🟢 Fastest | 🟡 Network   | 🟢 Fast        |

## StorageService API

The main interface for all storage operations:

### Core Methods

```dart
class StorageService {
  /// Initialize with typed configuration
  Future<void> initializeWithConfig(StorageConfig config);

  /// Save file with optional commit message
  Future<String> saveFile(String path, String content, {String? message});

  /// Read file content, returns null if not found
  Future<String?> readFile(String path);

  /// Remove file with optional commit message
  Future<void> removeFile(String path, {String? message});

  /// List files in directory
  Future<List<String>> listDirectory(String path);

  /// Restore file to previous version
  Future<void> restoreData(String path, {String? versionId});

  /// Sync with remote (if supported)
  Future<void> syncRemote({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  });

  /// Check authentication status
  Future<bool> isAuthenticated();

  /// Access underlying provider
  StorageProvider get provider;
}
```

### Configuration Classes

```dart
// FileSystem configuration
final fsConfig = FileSystemConfig(
  basePath: '/path/to/data',
  databaseName: 'app_db', // For web
);

// GitHub API configuration
final ghConfig = GitHubApiConfig(
  authToken: 'token',
  repositoryOwner: 'owner',
  repositoryName: 'repo',
  branchName: 'main',
);

// Offline Git configuration
final gitConfig = OfflineGitConfig(
  localPath: '/repo/path',
  branchName: 'main',
  authorName: 'Author Name',
  authorEmail: 'author@email.com',
  remoteUrl: 'https://github.com/user/repo.git',
  sshKeyPath: '/path/to/key', // or httpsToken: 'token'
);
```

## Smart Provider Selection

Let the library recommend the best provider for your needs:

```dart
// Define your requirements
final requirements = ProviderRequirements(
  needsVersionControl: true,
  needsOffline: true,
  hasGitCli: true,
  isWeb: false,
  needsCollaboration: true,
);

// Get recommendation
final recommendation = ProviderSelector.recommend(requirements);
print('Recommended: ${recommendation.providerType}');
print('Reason: ${recommendation.reason}');
print('Score: ${recommendation.score}/100');

// Create service using recommendation
final service = await StorageFactory.create(recommendation.configTemplate);
```

### Use Case-Based Selection

```dart
// Quick selection based on use case description
final requirements = ProviderSelector.fromUseCase('team collaboration project');
final recommendation = ProviderSelector.recommend(requirements);
final service = await StorageFactory.create(recommendation.configTemplate);
```

## Advanced Features

### Path Normalization

Cross-platform path handling:

```dart
// Normalize paths for different providers
final path = 'folder\\subfolder//file.txt';
final normalizedPath = PathNormalizer.normalize(path, ProviderType.filesystem);

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

### Version Control Features

When using Git-based providers, you can leverage version control features:

```dart
// Save with meaningful commit messages
await storageService.saveFile(
  'docs/api.md',
  apiDocumentation,
  message: 'Update API documentation with new endpoints',
);

// Restore to previous version
await storageService.restoreData('docs/api.md', versionId: 'abc123');

// Sync with remote repository
await storageService.syncRemote(
  pullMergeStrategy: 'merge',
  pushConflictStrategy: 'rebase-local',
);
```

## Error Handling

Comprehensive exception hierarchy:

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
} on StorageException catch (e) {
  print('General storage error: $e');
}
```

## Flutter Integration

### State Management

```dart
// Using with ChangeNotifier
class AppState extends ChangeNotifier {
  StorageService? _storageService;
  bool busy = false;
  String? error;

  Future<void> initializeStorage(String workspacePath) async {
    busy = true;
    notifyListeners();

    try {
      final config = FileSystemConfig(basePath: workspacePath);
      _storageService = await StorageFactory.create(config);
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

// Using with Provider
ChangeNotifierProvider(
  create: (_) => AppState(),
  child: MyApp(),
)
```

### Async File Operations

```dart
// Loading state management
Future<void> loadData() async {
  setState(() => isLoading = true);

  try {
    final content = await storageService.readFile('data.json');
    if (content != null) {
      setState(() => data = jsonDecode(content));
    }
  } catch (e) {
    setState(() => error = e.toString());
  } finally {
    setState(() => isLoading = false);
  }
}
```

## Testing

### Mock Storage for Testing

```dart
// Create a test storage service
final testConfig = FileSystemConfig(basePath: '/tmp/test');
final testService = await StorageFactory.createFileSystem(testConfig);

// Use in tests
test('should save and retrieve data', () async {
  await testService.saveFile('test.txt', 'test content');
  final content = await testService.readFile('test.txt');
  expect(content, equals('test content'));
});
```

## Platform Support

| Platform | FileSystem   | GitHub API | Offline Git |
| -------- | ------------ | ---------- | ----------- |
| Desktop  | ✅ Full      | ✅ Full    | ✅ Full     |
| Mobile   | ✅ Full      | ✅ Full    | ✅ Limited  |
| Web      | ❌ IndexedDB | ✅ Full    | ❌ None     |

## Requirements

- Dart SDK: `>=3.0.0 <4.0.0`
- Flutter: `>=3.0.0` (for Flutter projects)
- For Git operations: Git CLI installed and in PATH

## Examples

Check out the comprehensive examples in the `example/` directory:

- **`todo_app/`** - Complete Flutter todo application
- **`basic_usage.dart`** - Simple file operations
- **`github_api_usage.dart`** - GitHub API integration
- **`git_usage.dart`** - Git-based storage
- **`provider_factory_usage.dart`** - StorageFactory usage patterns

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

For more information and detailed documentation, visit our [GitHub repository](https://github.com/xsoulspace/universal_storage_sync).
