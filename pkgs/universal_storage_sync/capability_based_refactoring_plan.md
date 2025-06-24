# Capability-Based Architecture Refactoring Plan

## Overview

This document outlines a comprehensive refactoring strategy to transform the current monolithic storage providers into a flexible, capability-based architecture. The goal is to break down large provider files into focused, testable components while maintaining backward compatibility.

## Current Problems

### Monolithic Providers

- `OfflineGitStorageProvider`: 669 lines handling file operations, git commands, remote sync, and conflict resolution
- `GitHubApiStorageProvider`: 509 lines mixing API calls, authentication, and repository management
- Mixed responsibilities make code hard to maintain, test, and extend

### Poor Capability System

- `VersionControlCapable` mixin throws `UnsupportedOperationException` for all methods
- No way to detect what capabilities a provider actually supports
- One-size-fits-all interface doesn't match provider realities

### Testing Challenges

- Can't test individual concerns in isolation
- Large provider classes make unit testing complex
- Mocking entire providers is cumbersome

## Proposed Solution: Capability-Based Architecture

### Core Principles

1. **Single Responsibility** - Each service handles one concern
2. **Composition over Inheritance** - Providers compose services
3. **Explicit Capabilities** - Providers declare what they support
4. **Runtime Discovery** - Check capabilities dynamically
5. **Incremental Migration** - Maintain backward compatibility

## Refactoring Phases

### Phase 1: Service Extraction (Immediate Impact)

Extract focused service classes from monolithic providers:

```
src/
├── providers/
│   ├── offline_git_storage_provider.dart    # Becomes orchestrator (~100 lines)
│   ├── github_api_storage_provider.dart     # Becomes orchestrator (~80 lines)
│   └── services/
│       ├── local_file_service.dart          # Local file system operations
│       ├── git_operations_service.dart      # Pure git commands
│       ├── remote_sync_service.dart         # Pull/push/conflict resolution
│       ├── github_api_service.dart          # GitHub API wrapper
│       ├── conflict_resolution_service.dart # Conflict resolution strategies
│       └── authentication_service.dart      # Token/credential management
```

#### Service Responsibilities

**LocalFileService**

```dart
class LocalFileService {
  Future<String> createFile(String path, String content);
  Future<String?> readFile(String path);
  Future<void> updateFile(String path, String content);
  Future<void> deleteFile(String path);
  Future<List<String>> listFiles(String directory);
}
```

**GitOperationsService**

```dart
class GitOperationsService {
  Future<String> commit(String message, List<String> files);
  Future<List<CommitInfo>> getHistory({String? filePath, int? limit});
  Future<void> createBranch(String name);
  Future<List<String>> listBranches();
  Future<void> switchBranch(String name);
}
```

**RemoteSyncService**

```dart
class RemoteSyncService {
  Future<void> sync({String? pullStrategy, String? pushStrategy});
  Future<void> pull(String strategy);
  Future<void> push(String strategy);
  Future<void> handleConflicts(ConflictResolutionStrategy strategy);
}
```

**GitHubApiService**

```dart
class GitHubApiService {
  Future<List<VcRepository>> listRepositories();
  Future<VcRepository> createRepository(VcCreateRepositoryRequest request);
  Future<GitHubFile?> getFile(String path);
  Future<String> createFile(String path, String content, String message);
  Future<String> updateFile(String path, String content, String message, String sha);
}
```

#### Refactored Provider Example

```dart
class OfflineGitStorageProvider extends StorageProvider {
  late final LocalFileService _fileService;
  late final GitOperationsService _gitService;
  late final RemoteSyncService _syncService;

  @override
  Future<void> initWithConfig(StorageConfig config) async {
    // Initialize services with config
    _fileService = LocalFileService(config.localPath);
    _gitService = GitOperationsService(config.localPath);
    _syncService = RemoteSyncService(config);
  }

  @override
  Future<String> createFile(String path, String content, {String? commitMessage}) async {
    await _fileService.createFile(path, content);
    return _gitService.commit(commitMessage ?? 'Create file: $path', [path]);
  }

  @override
  Future<void> sync() => _syncService.sync();
}
```

### Phase 2: Capability System Redesign

Replace monolithic `VersionControlCapable` with focused capability mixins:

#### Granular Capability Mixins

```dart
mixin FileOperationsCapable {
  bool get supportsFileOperations => true;

  Future<String> createFile(String path, String content, {String? commitMessage});
  Future<String?> getFile(String path);
  Future<String> updateFile(String path, String content, {String? commitMessage});
  Future<void> deleteFile(String path, {String? commitMessage});
  Future<List<String>> listFiles(String directory);
}

mixin CommitCapable {
  bool get supportsCommits => true;

  Future<String> commit(String message, {List<String>? files});
  Future<List<CommitInfo>> getHistory({String? filePath, int? limit});
  Future<CommitInfo?> getCommit(String commitId);
  Future<String?> getFileAtCommit(String filePath, String commitId);
}

mixin BranchCapable {
  bool get supportsBranching => true;

  Future<void> createBranch(String name, {String? fromCommit});
  Future<void> switchBranch(String name);
  Future<List<String>> listBranches();
  Future<String> getCurrentBranch();
  Future<void> mergeBranch(String name, {String? message});
  Future<void> deleteBranch(String name, {bool force = false});
}

mixin RemoteSyncCapable {
  bool get supportsRemoteSync => true;

  Future<void> sync({String? pullStrategy, String? pushStrategy});
  Future<void> pull({String? strategy});
  Future<void> push({String? strategy});
}

mixin RepositoryManagementCapable {
  bool get supportsRepositoryManagement => true;

  Future<List<VcRepository>> listRepositories();
  Future<VcRepository> createRepository(VcCreateRepositoryRequest request);
  Future<VcRepository> getRepositoryInfo();
  Future<void> setRepository(VcRepositoryName name);
}

mixin AuthenticationCapable {
  bool get supportsAuthentication => true;

  Future<bool> isAuthenticated();
  Future<void> authenticate(Map<String, dynamic> credentials);
  Future<void> refreshAuthentication();
}
```

#### Capability Detection Interface

```dart
abstract class CapabilityProvider {
  /// Gets a specific capability if supported
  T? getCapability<T>();

  /// Checks if a capability is supported
  bool hasCapability<T>();

  /// Lists all supported capabilities
  List<Type> getSupportedCapabilities();
}
```

### Phase 3: Capability-Based Providers

Providers mix in only what they actually support:

```dart
class OfflineGitStorageProvider extends StorageProvider
    with FileOperationsCapable, CommitCapable, BranchCapable, RemoteSyncCapable
    implements CapabilityProvider {

  // Service composition
  late final LocalFileService _fileService;
  late final GitOperationsService _gitService;
  late final RemoteSyncService _syncService;

  @override
  T? getCapability<T>() {
    if (T == FileOperationsCapable) return this as T;
    if (T == CommitCapable) return this as T;
    if (T == BranchCapable) return this as T;
    if (T == RemoteSyncCapable) return this as T;
    return null;
  }

  @override
  bool hasCapability<T>() => getCapability<T>() != null;

  // Delegate to services
  @override
  Future<String> createFile(String path, String content, {String? commitMessage}) =>
    _fileService.createFile(path, content).then((_) =>
      _gitService.commit(commitMessage ?? 'Create file: $path', [path]));
}

class GitHubApiStorageProvider extends StorageProvider
    with FileOperationsCapable, RepositoryManagementCapable, AuthenticationCapable
    implements CapabilityProvider {

  late final GitHubApiService _apiService;

  // GitHub API has limited capabilities
  @override
  bool get supportsCommits => false;
  @override
  bool get supportsBranching => false;
  @override
  bool get supportsRemoteSync => false;

  @override
  T? getCapability<T>() {
    if (T == FileOperationsCapable) return this as T;
    if (T == RepositoryManagementCapable) return this as T;
    if (T == AuthenticationCapable) return this as T;
    return null;
  }
}
```

### Phase 4: Runtime Capability Detection

Enable dynamic capability checking:

```dart
// Usage examples
Future<void> performCommit(StorageProvider provider, String message) async {
  if (provider.hasCapability<CommitCapable>()) {
    final commitCapability = provider.getCapability<CommitCapable>()!;
    await commitCapability.commit(message);
  } else {
    throw UnsupportedOperationException('Provider does not support commits');
  }
}

// Or using pattern matching
switch (provider) {
  case CommitCapable(supportsCommits: true) && BranchCapable():
    // Provider supports both commits and branches
    await provider.createBranch('feature-branch');
    await provider.commit('Initial commit');
  case FileOperationsCapable():
    // Provider only supports basic file operations
    await provider.createFile('README.md', 'Hello World');
  default:
    throw UnsupportedOperationException('Unsupported provider type');
}
```

## Implementation Strategy

### Step 1: Service Extraction (Week 1-2)

1. Create service classes in `src/providers/services/`
2. Extract logic from `OfflineGitStorageProvider` into services
3. Update provider to delegate to services
4. Write unit tests for each service
5. Repeat for `GitHubApiStorageProvider`

### Step 2: Capability Mixins (Week 3)

1. Create new capability mixins in `src/capabilities/`
2. Keep existing `VersionControlCapable` for backward compatibility
3. Add capability detection interface
4. Update providers to implement new capabilities

### Step 3: Provider Migration (Week 4)

1. Update providers to use new capability system
2. Add capability detection methods
3. Update tests to use capability-based testing
4. Document capability matrix for each provider

### Step 4: Consumer Updates (Week 5)

1. Update example apps to use capability detection
2. Add capability-aware error handling
3. Create migration guide for existing consumers
4. Deprecate old capability system

## Benefits

### Immediate (Phase 1)

- **Reduced file sizes**: Providers become 50-100 line orchestrators
- **Better testability**: Test services independently
- **Clear separation**: Each service has single responsibility
- **Easier debugging**: Isolated concerns are easier to troubleshoot

### Medium-term (Phase 2-3)

- **Granular capabilities**: Mix and match what providers support
- **Compile-time safety**: No unsupported method calls
- **Flexible architecture**: Easy to add new capabilities
- **Better documentation**: Clear capability matrix

### Long-term (Phase 4)

- **Runtime discovery**: Check capabilities dynamically
- **Partial implementations**: Providers support what makes sense
- **Extensibility**: New providers and capabilities without breaking changes
- **Plugin architecture**: Third-party providers can implement specific capabilities

## Testing Strategy

### Service-Level Testing

```dart
// Test services in isolation
test('LocalFileService creates file correctly', () async {
  final service = LocalFileService('/tmp/test');
  await service.createFile('test.txt', 'content');

  final content = await service.readFile('test.txt');
  expect(content, equals('content'));
});
```

### Capability Testing

```dart
// Test capability behavior
test('OfflineGitStorageProvider supports all expected capabilities', () {
  final provider = OfflineGitStorageProvider();

  expect(provider.hasCapability<FileOperationsCapable>(), isTrue);
  expect(provider.hasCapability<CommitCapable>(), isTrue);
  expect(provider.hasCapability<BranchCapable>(), isTrue);
  expect(provider.hasCapability<RemoteSyncCapable>(), isTrue);
});
```

### Integration Testing

```dart
// Test provider orchestration
test('Provider delegates file operations correctly', () async {
  final provider = OfflineGitStorageProvider();
  await provider.initWithConfig(testConfig);

  final commitHash = await provider.createFile('test.txt', 'content');
  expect(commitHash, isNotEmpty);

  final content = await provider.getFile('test.txt');
  expect(content, equals('content'));
});
```

## Migration Guide

### For Library Maintainers

1. **Phase 1**: Extract services, maintain existing provider APIs
2. **Phase 2**: Add new capability mixins alongside existing ones
3. **Phase 3**: Update providers to implement new capabilities
4. **Phase 4**: Add capability detection, deprecate old system

### For Library Consumers

1. **Immediate**: No changes required (backward compatible)
2. **Recommended**: Start using capability detection for new features
3. **Future**: Migrate from direct provider usage to capability-based usage

### Breaking Changes

- None in Phase 1-3 (fully backward compatible)
- Phase 4 may deprecate some methods (with migration period)

## File Structure After Refactoring

```
src/
├── capabilities/
│   ├── authentication_capable.dart
│   ├── commit_capable.dart
│   ├── branch_capable.dart
│   ├── file_operations_capable.dart
│   ├── remote_sync_capable.dart
│   ├── repository_management_capable.dart
│   └── version_control_capable.dart (deprecated)
├── providers/
│   ├── offline_git_storage_provider.dart (~100 lines)
│   ├── github_api_storage_provider.dart (~80 lines)
│   └── services/
│       ├── authentication_service.dart
│       ├── conflict_resolution_service.dart
│       ├── git_operations_service.dart
│       ├── github_api_service.dart
│       ├── local_file_service.dart
│       └── remote_sync_service.dart
├── models/ (existing)
├── storage_exceptions.dart (existing)
└── storage_provider.dart (updated with capability detection)
```

## Conclusion

This capability-based refactoring transforms the current monolithic architecture into a flexible, maintainable system. By extracting services and implementing granular capabilities, we achieve better separation of concerns, improved testability, and a foundation for future extensibility.

The phased approach ensures backward compatibility while providing immediate benefits. Each phase builds upon the previous one, allowing for incremental adoption and reduced risk.
