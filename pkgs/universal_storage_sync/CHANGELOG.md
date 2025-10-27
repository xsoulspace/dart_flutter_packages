# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-dev.9] - 2025-10-27

- refactor: StorageService from `universal_storage_sync` package to `universal_storage_interface` package

## [0.1.0-dev.8] - 2025-10-25

- feat: add `StorageProviderRegistry.dispose` method
- chore: update interface dependency to 0.1.0-dev.8

## [0.1.0-dev.7] - 2025-10-25

- fixed todo_file_app example to latest changes
- chore: update interface dependency to 0.1.0-dev.7

## [0.1.0-dev.6] - 2025-10-18

- chore: from_json_to_json ^0.3.0

## [0.1.0-dev.5] - 2025-08-09

### Changed

- moved `macos_bookmark.dart` and `file_path_config.dart` to `universal_storage_interface`

## [0.1.0-dev.4] - 2025-08-09

### Changed

- Stabilized APIs for initial public release
- Promoted previous `-dev` changes to stable
- Updated documentation and links for publication

## [0.1.0-dev.3] - 2025-06-27

- feat: Add `FilePathConfig` and `FilePath` models for storing file path and macOS bookmark.
- feat: moved `MacOSBookmark` from `utils` package.

## [0.1.0-dev.2] - 2025-06-22

- perf: Readme update

## [0.1.0-dev.1] - 2025-06-21

### Added

- `MacOSBookmark` class for macOS security-scoped bookmarks
- `MacOSBookmarkManager` class for managing macOS security-scoped bookmarks
- `MacOSBookmark.fromBase64` constructor
- `MacOSBookmark.fromDirectory` constructor

## [0.0.0] - 2025-06-21

### Added

- **Stage 1 Complete**: Core abstractions and FileSystem provider
- `StorageProvider` abstract class defining the contract for all storage providers
- `StorageService` main service class providing unified API
- `FileSystemStorageProvider` for local file system operations
- Comprehensive exception hierarchy:
  - `StorageException` (base)
  - `AuthenticationException`
  - `FileNotFoundException`
  - `NetworkException`
  - `GitConflictException`
  - `SyncConflictException`
  - `UnsupportedOperationException`
- Structured configuration classes:
  - `StorageConfig` (base)
  - `FileSystemConfig`
  - `OfflineGitConfig` (for future use)
  - `GitHubApiConfig` (for future use)
- `OfflineGitStorageProvider` placeholder (Stage 2 implementation)
- Comprehensive test suite for FileSystem provider
- Basic usage examples
- Cross-platform support (Desktop, Mobile, Web with IndexedDB)

### Features

- Create, read, update, delete files
- List directory contents
- Nested directory creation
- Type-safe configuration system
- Graceful handling of unsupported operations
- Comprehensive error handling

### Dependencies

- `git: ^2.3.1` (for future Git operations)
- `github: ^9.25.0` (for future GitHub API integration)
- `http: ^1.1.0`
- `path: ^1.8.3`
- `meta: ^1.9.1`

### Development Dependencies

- `test: ^1.24.0`
- `mockito: ^5.4.2`
- `build_runner: ^2.4.7`
- `lints: ^3.0.0`

## [0.0.0] - 2025-06-21

### Added

- **Stage 2 Complete**: OfflineGitStorageProvider with local Git operations
- Full `OfflineGitStorageProvider` implementation with local Git repository support
- Automatic Git repository initialization and configuration
- Git-based file operations with automatic commits:
  - `createFile()` with `git add` and `git commit`
  - `updateFile()` with `git add` and `git commit`
  - `deleteFile()` with `git rm` and `git commit`
  - `getFile()` from working directory
  - `listFiles()` with Git-aware filtering (excludes .git directory)
- Version control features:
  - `restore()` method for file restoration to previous versions
  - Support for restoring to specific commit hashes or HEAD
  - Automatic commit hash generation and return
- Git repository management:
  - Automatic repository initialization if not exists
  - Branch creation and switching
  - Git user configuration (name and email)
  - Initial commit creation for empty repositories
- Enhanced error handling for Git operations
- Comprehensive test suite with 36 passing tests covering:
  - Repository initialization scenarios
  - File operations with Git integration
  - Version control features
  - Error scenarios and edge cases
  - Integration with StorageService
- `example/git_usage.dart` demonstrating Git-specific features
- Updated documentation with Git usage examples

### Features

- All Stage 1 features plus:
- Local Git version control
- Automatic commit generation with meaningful default messages
- File restoration to previous versions
- Git-aware directory listing
- Support for nested directory creation with Git tracking
- Commit hash returns for tracking changes

## [0.0.0] - 2025-06-21

### Added

- **Stage 3 Complete**: Remote Git synchronization for OfflineGitStorageProvider
- Comprehensive remote Git synchronization with `sync()` method
- Enhanced `OfflineGitConfig` with remote configuration options:
  - `remoteUrl`, `remoteName`, `remoteType`, `remoteApiSettings`
  - `defaultPullStrategy`, `defaultPushStrategy`
  - `conflictResolution` strategy configuration
  - `sshKeyPath`, `httpsToken` for authentication
- Four conflict resolution strategies:
  - `clientAlwaysRight` (default) - Local changes take precedence
  - `serverAlwaysRight` - Remote changes take precedence
  - `manualResolution` - Throws exception for manual intervention
  - `lastWriteWins` - Timestamp-based resolution
- Pull strategies: `merge`, `rebase`, `ff-only`
- Push strategies: `rebase-local`, `force-with-lease`, `fail-on-conflict`
- New remote operation exceptions:
  - `RemoteNotFoundException`
  - `AuthenticationFailedException`
  - `MergeConflictException`
  - `NetworkTimeoutException`
  - `RemoteAccessDeniedException`
- Smart sync support detection based on remote URL configuration
- Retry mechanisms with exponential backoff for network operations
- Remote repository validation and access checking
- Comprehensive test suite with 56 passing tests covering:
  - Remote setup and configuration
  - Conflict resolution strategies
  - Sync strategies and error handling
  - Authentication configuration
  - Integration with StorageService
  - Configuration validation

### Features

- All Stage 1 & 2 features plus:
- Remote Git repository synchronization
- "Client is always right" conflict resolution philosophy
- Configurable pull and push strategies
- Robust network error handling with retries
- SSH and HTTPS authentication support
- Graceful handling of providers without remote URLs
- Dynamic sync support detection

### Dependencies

- Added `retry: ^3.1.2` for robust network operations

## [Unreleased]

### Planned for Stage 4

- GitHub API integration for repository management
- Remote repository creation and validation
- Enhanced error reporting for Git operations

### Planned for Stage 5

- Lightweight API-only providers
- Direct GitHub API provider
- Additional cloud storage providers
