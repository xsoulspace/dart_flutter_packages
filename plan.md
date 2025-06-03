# Universal Storage Sync Dart Package: Project Plan

## 1. Project Goal

To create a developer-friendly, cross-platform Dart package named `universal_storage_sync`. This package will provide a unified API for:

- Initializing various storage providers.
- Performing CRUD (Create, Read, Update, Delete) operations on files.
- Listing files within directories.
- Restoring files or entire datasets.
- Supporting local file systems and Git-based version control (offline-first with remote sync capabilities for GitHub and other Git remotes).
- Implementing a "client is always right" conflict resolution strategy for Git-based synchronization where appropriate and configurable.

## 2. Core API Design

The architecture revolves around a `StorageProvider` interface and a `StorageService` class that consumes it.

### 2.1. `StorageProvider` (Abstract Class)

This interface defines the contract for all storage mechanisms.

```dart
/// {@template storage_provider}
/// Defines the contract for a storage provider.
/// {@endtemplate}
abstract class StorageProvider {
  /// {@template storage_provider.init}
  /// Initializes the storage provider with the given [config].
  /// The [config] map contains provider-specific settings.
  /// {@endtemplate}
  Future<void> init(Map<String, dynamic> config);

  /// {@template storage_provider.isAuthenticated}
  /// Checks if the provider is currently authenticated or properly configured.
  /// {@endtemplate}
  Future<bool> isAuthenticated();

  /// {@template storage_provider.createFile}
  /// Creates a new file at [path] with [content].
  /// For version-controlled providers, an optional [commitMessage] can be provided.
  /// {@endtemplate}
  Future<String> createFile(String path, String content, {String? commitMessage});

  /// {@template storage_provider.getFile}
  /// Retrieves the content of the file at [path]. Returns `null` if not found.
  /// {@endtemplate}
  Future<String?> getFile(String path);

  /// {@template storage_provider.updateFile}
  /// Updates an existing file at [path] with new [content].
  /// An optional [commitMessage] can be provided for version-controlled providers.
  /// {@endtemplate}
  Future<String> updateFile(String path, String content, {String? commitMessage});

  /// {@template storage_provider.deleteFile}
  /// Deletes the file at [path].
  /// An optional [commitMessage] can be provided for version-controlled providers.
  /// {@endtemplate}
  Future<void> deleteFile(String path, {String? commitMessage});

  /// {@template storage_provider.listFiles}
  /// Lists all files and directories within the specified [directoryPath].
  /// {@endtemplate}
  Future<List<String>> listFiles(String directoryPath);

  /// {@template storage_provider.restore}
  /// Restores a file or set of files. Behavior is provider-dependent.
  /// [versionId] can specify a version (e.g., Git commit hash).
  /// {@endtemplate}
  Future<void> restore(String path, {String? versionId});

  /// {@template storage_provider.supportsSync}
  /// Indicates if the provider supports remote synchronization. Defaults to `false`.
  /// {@endtemplate}
  bool get supportsSync => false;

  /// {@template storage_provider.sync}
  /// Synchronizes with a remote store, if applicable.
  /// Throws [UnsupportedOperationException] if not supported.
  /// [pullMergeStrategy] and [pushConflictStrategy] can guide behavior.
  /// {@endtemplate}
  Future<void> sync({
    String? pullMergeStrategy, // e.g., 'rebase', 'merge', 'ff-only'
    String? pushConflictStrategy, // e.g., 'rebase-local', 'force-with-lease'
  }) {
    throw UnsupportedOperationException('This provider does not support sync.');
  }
}
```

### 2.2. `StorageService` (Main Public Class)

The primary entry point for developers using the package.

```dart
/// {@template storage_service}
/// A service class providing a unified API for file storage operations
/// using a configured [StorageProvider].
/// {@endtemplate}
class StorageService {
  final StorageProvider _provider;

  /// {@macro storage_service}
  StorageService(this._provider);

  /// {@template storage_service.initialize}
  /// Initializes the underlying storage provider with [config].
  /// Must be called before other operations.
  /// {@endtemplate}
  Future<void> initialize(Map<String, dynamic> config) => _provider.init(config);

  /// {@template storage_service.saveFile}
  /// Saves (creates or updates) a file at [path] with [content].
  /// Uses [message] as commit message for version-controlled storage.
  /// {@endtemplate}
  Future<String> saveFile(String path, String content, {String? message}) async {
    // Simplified: actual implementation would check existence more robustly
    // or rely on provider's createFile/updateFile to handle it.
    try {
      await _provider.getFile(path); // Check if file exists
      return _provider.updateFile(path, content, commitMessage: message);
    } catch (e) { // Assuming specific exception like FileNotFoundException
      return _provider.createFile(path, content, commitMessage: message);
    }
  }

  /// {@template storage_service.readFile}
  /// Reads content of file at [path]. Returns `null` if not found.
  /// {@endtemplate}
  Future<String?> readFile(String path) => _provider.getFile(path);

  /// {@template storage_service.removeFile}
  /// Removes file at [path]. [message] for version-controlled storage.
  /// {@endtemplate}
  Future<void> removeFile(String path, {String? message}) =>
      _provider.deleteFile(path, commitMessage: message);

  /// {@template storage_service.listDirectory}
  /// Lists files/subdirectories within [path].
  /// {@endtemplate}
  Future<List<String>> listDirectory(String path) =>
      _provider.listFiles(path);

  /// {@template storage_service.restoreData}
  /// Restores data at [path], optionally to [versionId].
  /// {@endtemplate}
  Future<void> restoreData(String path, {String? versionId}) =>
      _provider.restore(path, versionId: versionId);

  /// {@template storage_service.syncRemote}
  /// Synchronizes local data with the configured remote storage provider,
  /// if supported.
  /// {@endtemplate}
  Future<void> syncRemote({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  }) async {
    if (_provider.supportsSync) {
      await _provider.sync(
        pullMergeStrategy: pullMergeStrategy,
        pushConflictStrategy: pushConflictStrategy,
      );
    } else {
      // Log or handle providers not supporting sync
      print('The configured storage provider does not support remote synchronization.');
      // Optionally throw UnsupportedOperationException
    }
  }
}
```

## 3. Provider Implementations

### 3.1. `FileSystemStorageProvider`

- **Dependencies:** `dart:io` (non-web), `sembast_web` or similar (for web).
- **Configuration (`init`):**
  - Non-Web: `{'basePath': String}` (Path to the root directory for storage).
  - Web: `{'databaseName': String}` (For IndexedDB).
- **Operations:** Direct file system operations (or IndexedDB operations on web).
- **`sync`:** Not supported (`supportsSync` returns `false`).

### 3.2. `OfflineGitStorageProvider`

Offline-first provider using a local Git repository, with explicit remote synchronization.

- **Primary Dependency:** `package:git` (for local Git CLI operations).
- **Optional Dependencies:** `package:github` (for API interactions with specific remotes like checking existence, creating repos, richer error reporting).
- **Configuration (`init`):**
  - `'localPath': String` (Required: Path to the local Git repository; will be initialized if not one).
  - `'branchName': String` (Required: Primary local and remote branch, e.g., "main").
  - `'authorName': String` (Optional: For Git commits).
  - `'authorEmail': String` (Optional: For Git commits).
  - **Remote Config (Optional, for `sync`):**
    - `'remoteName': String` (Defaults to "origin").
    - `'remoteUrl': String` (URL of the remote Git repository).
    - `'remoteType': String` (Optional: "github", "custom_git". Helps select API helpers).
    - `'remoteApiSettings': Map<String, dynamic>` (Optional: API-specific settings like `authToken`, `repositoryOwner`/`repositoryName` for GitHub. Used for advanced features like remote repo creation/validation).
- **Authentication for Git Operations:** Relies on system's Git setup (SSH keys, credential helpers). For HTTPS, PATs can be embedded in `remoteUrl` (with documented security considerations) or credential helper configured.
- **Core File Operations (`createFile`, `getFile`, `updateFile`, `deleteFile`, `listFiles`):**
  - Interact directly with the local file system within `localPath`.
  - Use `package:git` to perform `git add`, `git commit`, `git rm`, `git ls-files` as appropriate after file system changes.
- **`sync({String? pullMergeStrategy, String? pushConflictStrategy})`:**
  - **Pull Phase:**
    1.  `git pull <remoteName> <branchName>` (using `package:git`). Strategy (e.g., `--rebase`, `--ff-only`) can be influenced by `pullMergeStrategy`.
    2.  If conflicts occur that Git can't auto-resolve, throw `SyncConflictException`. Local repo remains in conflicted state for manual resolution.
  - **Push Phase:**
    1.  `git push <remoteName> <branchName>` (using `package:git`).
    2.  **"Client is always right" for push conflicts (non-fast-forward):**
        - Default `pushConflictStrategy` (e.g., `'rebase-local'`):
          1.  `git pull --rebase <remoteName> <branchName>` (attempts to re-apply local commits on top of fetched remote changes).
          2.  If rebase successful: `git push <remoteName> <branchName>`.
          3.  If rebase conflicts: throw `SyncConflictException`.
        - Aggressive `pushConflictStrategy` (e.g., `'force-with-lease'`, configurable and clearly documented due to risk):
          1.  `git push --force-with-lease <remoteName> <branchName>`. This overwrites remote history.
- **`restore(String path, {String? versionId})`:** Uses `git checkout <versionId> -- <path>` or `git checkout HEAD -- <path>`.
- **Advanced Remote Interaction (via `github` package if `remoteApiSettings` provided):**
  - During `init` or on demand: Check if remote repository exists.
  - Attempt to create remote repository if it doesn't exist and user allows/configures.

### 3.3. (Optional) Lightweight API-Only Providers

- `GithubApiProvider`
- **Dependencies:** `package:github`.
- These would not use local Git clones but interact directly with the respective APIs for all operations.
- Suited for scenarios where no local offline capability is needed or where Git CLI is unavailable/undesirable.
- `sync` would not be applicable in the same way as `OfflineGitStorageProvider`.

## 4. Configuration & Initialization

- **Structured Config:** Provide static helper methods or dedicated configuration classes for each provider to make `init` parameters discoverable and type-safe.
  Example: `FileSystemConfig(basePath: '/path')`, `OfflineGitConfig(localPath: '...', remoteUrl: '...')`.
- **Folder/File Picking:** The consuming application (not this library) will be responsible for UI elements like folder/file pickers (e.g., using `package:file_picker`). The selected paths are then passed into the configuration objects.

## 5. Cross-Platform Strategy

- **`FileSystemStorageProvider`:**
  - Non-Web (Mobile, Desktop): `dart:io`.
  - Web: `sembast_web` (or similar) for IndexedDB.
- **`OfflineGitStorageProvider`:**
  - Core functionality relies on `package:git` (Git CLI wrapper). Git must be installed and in PATH.
  - Works on Desktop, Server, and potentially Mobile if Git CLI is available (less common).
  - API interactions via `package:github` are platform-agnostic.
- **API-Only Providers (Optional):**
  - `package:github` are platform-agnostic.

## 6. Key Dependencies

- `git: ^2.3.1` (or latest)
- `github: ^9.25.0` (or latest)
- `http` (likely transitive)
- `path_provider` (Flutter, for suggesting default local paths in examples/consuming app)
- `sembast_web` (or alternative for IndexedDB on web)
- `test`, `mockito` (for testing)
- `meta` (for annotations like `@required`)

## 7. Development Roadmap & Stages

1.  **Stage 1: Core Abstractions & FileSystem Provider**

    - Define `StorageProvider` interface (with `sync` methods) and `StorageService`.
    - Implement `FileSystemStorageProvider` (for `dart:io` and web via IndexedDB).
    - Custom exceptions.
    - Unit tests and basic examples.

2.  **Stage 2: `OfflineGitStorageProvider` - Local Operations**

    - Implement core local Git operations for `OfflineGitStorageProvider` using `package:git` (init, add, commit, rm, file R/W).
    - No remote sync functionality yet.
    - Thorough testing of local Git interactions.

3.  **Stage 3: `OfflineGitStorageProvider` - Remote Sync**

    - Implement the `sync()` method for `OfflineGitStorageProvider`, including pull and push logic.
    - Implement "client is always right" strategies (e.g., rebase-local, optional force-push).
    - Handle authentication considerations for Git.
    - Extensive testing with actual Git remotes (e.g., a dedicated test GitHub repo).

4.  **Stage 4: `OfflineGitStorageProvider` - API-Assisted Features**

    - Integrate `package:github` for API interactions (e.g., check/create remote repo during `init` if `remoteApiSettings` are provided).

5.  **Stage 5: Refinements & Documentation**

    - Validate the API and the implementation.
    - Validate the examples.
    - Validate the structured configuration classes/helpers.
    - Validate the comprehensive examples (especially for Flutter).
    - Finalize documentation.

6.  **Stage 6: Binary Data Handling**
    - Address binary data handling.

## 8. Important Considerations

- **Binary Data:** The API currently assumes string content. For binary files, decide on a strategy:
  - Base64 encoding/decoding when using the string API.
  - Or, adapt the API to accept/return `Uint8List`.
- **Error Handling:** Define a clear hierarchy of custom exceptions (e.g., `StorageException`, `AuthenticationException`, `FileNotFoundException`, `NetworkException`, `GitConflictException`, `SyncConflictException`).
- **Security:**
  - Document secure PAT/token handling for Git remotes and API access.
  - Advise against embedding secrets directly in client-side code where possible.
- **Large Files:** Git is not ideal for very large binary files. This library will inherit Git's limitations. Consider documenting `git-lfs` as an external setup if users need it.
- **Atomicity:** Git operations involve multiple steps. Handle potential failures at each step and report clearly. True atomicity across file system and Git remote operations is complex.
- **GitLab Package Viability:** The `gitlab` package on pub.dev was last updated 3 years ago. Its current compatibility and feature set need to be assessed. If it's not suitable, direct HTTP calls to the GitLab API or finding an alternative package would be necessary.
