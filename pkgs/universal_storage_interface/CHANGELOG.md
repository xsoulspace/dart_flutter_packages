# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-dev.5] - 2025-08-09

### Changed

- moved `macos_bookmark.dart` and `file_path_config.dart` to `models.dart`

## [0.1.0-dev.4] - 2025-08-09

### Changed

- alignment update, same as 0.1.0-dev.3

## [0.1.0-dev.3] - 2025-08-09

### Added

- **Initial Release**: Core interfaces and models for universal storage providers
- `StorageProvider` abstract class defining the contract for all storage implementations
- `StorageService` main service class providing unified API
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
  - `OfflineGitConfig`
  - `GitHubApiConfig`
- Core models:
  - `FileEntry` for file/directory representation
  - `FileOperationResult` for operation results
  - Version control models (`VcRepositoryOwner`, `VcRepositoryName`, `VcBranchName`, `VcUrl`)
- Type-safe configuration system
- Comprehensive error handling framework

### Features

- Unified storage provider interface
- Cross-platform configuration models
- Version control aware models
- Exception hierarchy for robust error handling
- Type-safe configuration system

### Dependencies

- `from_json_to_json: ^0.2.1` - JSON serialization utilities
- `meta: ^1.16.0` - Metadata annotations

### Development Dependencies

- `lints: ^6.0.0` - Dart linting rules
- `xsoulspace_lints: ^0.1.0` - Custom linting rules

## [Unreleased]

### Planned

- Enhanced validation for configuration classes
- Additional utility models for common storage operations
- Migration helpers for configuration updates
