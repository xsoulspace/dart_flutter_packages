# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-01-XX

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

## [0.2.0] - 2024-01-XX

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

## [Unreleased]

### Planned for Stage 3

- Remote Git synchronization
- Pull and push operations
- Conflict resolution strategies
- "Client is always right" merge strategies

### Planned for Stage 4

- GitHub API integration for repository management
- Remote repository creation and validation
- Enhanced error reporting for Git operations

### Planned for Stage 5

- Lightweight API-only providers
- Direct GitHub API provider
- Additional cloud storage providers
