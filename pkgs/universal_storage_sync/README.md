# Universal Storage Sync

A lightweight foundation that provides a unified, type-safe API for file storage operations across multiple providers (Filesystem, GitHub API, Offline Git).

Important: Provider implementations live in dedicated packages. Add and register the providers you want to use in your app:

- Filesystem: `universal_storage_filesystem`
- GitHub API: `universal_storage_github_api`
- Offline Git: `universal_storage_git_offline`

## Features

- **Unified API**: Use `StorageService` regardless of provider
- **Type-safe configuration**: `FileSystemConfig`, `GitHubApiConfig`, `OfflineGitConfig`
- **Factory + Registry**: Create ready-to-use services via `StorageFactory` after provider registration
- **Version-control aware**: Commit messages, restore, and sync (for Git-based providers)
- **Retry + paths**: Helpers for retryable ops and cross-platform path normalization

## Installation

Add the core package plus the providers you need. While this package is in active development, use path or git dependencies as appropriate.

```yaml
dependencies:
  universal_storage_sync:
    path: ../universal_storage_sync

  # Choose one or more providers
  universal_storage_filesystem:
    path: ../universal_storage_filesystem
  universal_storage_github_api:
    path: ../universal_storage_github_api
  universal_storage_git_offline:
    path: ../universal_storage_git_offline
```

After adding a provider, register it at app startup so `StorageFactory` can resolve it:

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';

void bootstrapStorageRegistry() {
  StorageProviderRegistry.register<FileSystemConfig>(
    () => FileSystemStorageProvider(),
  );
  StorageProviderRegistry.register<GitHubApiConfig>(
    () => GitHubApiStorageProvider(),
  );
  StorageProviderRegistry.register<OfflineGitConfig>(
    () => OfflineGitStorageProvider(),
  );
}
```

## Quick Start

### Option A: Direct provider (simple)

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  final service = StorageService(FileSystemStorageProvider());
  await service.initializeWithConfig(FileSystemConfig(basePath: '/path/to/storage'));

  await service.saveFile('hello.txt', 'Hello, World!');
  final content = await service.readFile('hello.txt');
  print(content);

  final entries = await service.listDirectory('.');
  print(entries.map((e) => e.name).toList());
}
```

### Option B: Factory + registry (recommended for apps)

```dart
import 'package:universal_storage_sync/universal_storage_sync.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';

Future<void> main() async {
  // one-time registration in your app bootstrap
  StorageProviderRegistry.register<FileSystemConfig>(() => FileSystemStorageProvider());

  final service = await StorageFactory.create(
    FileSystemConfig(basePath: '/path/to/storage'),
  );

  await service.saveFile('hello.txt', 'Hello, World!');
}
```

## Real-World Example: Todo App

How this foundation is used in a Flutter todo app (simplified):

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
      final entries = await _storageService!.listDirectory('todos');
      final loadedTodos = <Todo>[];

      for (final entry in entries) {
        if (!entry.isDirectory && entry.name.endsWith('.yaml')) {
          final content = await _storageService!.readFile(entry.name);
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

Local filesystem. High performance. Not supported on web.

```dart
final service = StorageService(FileSystemStorageProvider());
await service.initializeWithConfig(FileSystemConfig(basePath: '/path/to/data'));
```

**Best for:** Desktop/mobile apps, offline-first, high performance local storage

### 🌐 GitHub API Provider

Cloud storage via GitHub REST API. No local Git required.

```dart
final service = StorageService(GitHubApiStorageProvider());
await service.initializeWithConfig(GitHubApiConfig(
  authToken: 'ghp_your_token_here',
  repositoryOwner: const VcRepositoryOwner('your-username'),
  repositoryName: const VcRepositoryName('your-repo'),
  branchName: VcBranchName.main,
));
```

**Best for:** Web apps, collaboration, cloud sync

**Features:**

- Full GitHub integration
- Automatic commit messages
- Branch management
- Collaboration features
- No local Git CLI required

### 🔄 Offline Git Provider

Local Git repository with optional remote sync.

```dart
final service = StorageService(OfflineGitStorageProvider());
await service.initializeWithConfig(OfflineGitConfig(
  localPath: '/path/to/repo',
  branchName: VcBranchName.main,
  authorName: 'Your Name',
  authorEmail: 'you@example.com',
  remoteUrl: const VcUrl('https://github.com/user/repo.git'),
  sshKeyPath: '/path/to/ssh/key',
));
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
| Web Support      | ❌ None    | ✅ Full      | ❌ None        |
| Performance      | 🟢 Fastest | 🟡 Network   | 🟢 Fast        |

## StorageService API

The main interface for all storage operations:

### Core Methods (current signatures)

```dart
class StorageService {
  Future<void> initializeWithConfig(StorageConfig config);

  Future<FileOperationResult> saveFile(
    String path,
    String content, {
    String? message,
  });

  Future<String?> readFile(String path);

  Future<FileOperationResult> removeFile(String path, {String? message});

  Future<List<FileEntry>> listDirectory(String path);

  Future<void> restoreData(String path, {String? versionId});

  Future<void> syncRemote({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  });

  Future<bool> isAuthenticated();

  StorageProvider get provider;
}
```

### Configuration Classes

```dart
// FileSystem configuration
final fsConfig = FileSystemConfig(basePath: '/path/to/data');

// GitHub API configuration
final ghConfig = GitHubApiConfig(
  authToken: 'token',
  repositoryOwner: const VcRepositoryOwner('owner'),
  repositoryName: const VcRepositoryName('repo'),
  branchName: VcBranchName.main,
);

// Offline Git configuration
final gitConfig = OfflineGitConfig(
  localPath: '/repo/path',
  branchName: VcBranchName.main,
  authorName: 'Author Name',
  authorEmail: 'author@email.com',
  remoteUrl: const VcUrl('https://github.com/user/repo.git'),
  sshKeyPath: '/path/to/key', // or httpsToken: 'token'
);
```

## Smart Provider Selection

Let the library recommend a provider based on your requirements (tutorial utility):

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

Retry helpers for robust operations (useful for network providers):

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

With Git-based providers you can leverage VC features:

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

Unified exception hierarchy (thrown by providers):

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

### Simple test using FileSystem provider

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

| Platform | FileSystem | GitHub API | Offline Git |
| -------- | ---------- | ---------- | ----------- |
| Desktop  | ✅ Full    | ✅ Full    | ✅ Full     |
| Mobile   | ✅ Full    | ✅ Full    | ✅ Limited  |
| Web      | ❌ None    | ✅ Full    | ❌ None     |

## Requirements

- Dart SDK: `>=3.8.1 <4.0.0`
- Flutter (optional): `>=3.0.0`
- For Git operations: Git CLI installed and on PATH

## Examples

See `example/` for runnable samples:

- `basic_usage.dart` – Filesystem operations
- `github_api_usage.dart` – GitHub API integration
- `git_usage.dart` – Offline Git with VC features
- `provider_factory_usage.dart` – Factory + registry patterns
- `todo_file_app/` and `todo_git_app/` – Full Flutter examples

## Contributing

Contributions welcome. Please read the Contributing Guide before submitting PRs.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

For more information and detailed documentation, visit the repository.
