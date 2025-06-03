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

## [Unreleased]

### Planned for Stage 2

- `OfflineGitStorageProvider` local Git operations
- File versioning and history
- Git-based file operations (add, commit, rm)
- Local Git repository initialization

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
