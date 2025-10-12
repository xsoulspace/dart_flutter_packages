# Changelog

This project follows [Semantic Versioning](https://semver.org/) (semver).  
Breaking changes will increment the major version, new features the minor, and bugfixes the patch.  
Always review the changelog before upgrading to a new version.

All notable changes to this project will be documented in this file.

## [0.2.0-beta.1] - 2025-10-12

### Changed

- **BREAKING**: Logger and FileWriter now require explicit initialization via `await logger.init()` after instantiation
- FileWriter initialization is no longer automatic in constructor, preventing unawaited futures
- This change ensures proper async initialization and prevents potential race conditions

### Migration Guide

**Before:**

```dart
void main() {
  final logger = Logger(LoggerConfig.debug());
  logger.info('APP', 'Application started');
}
```

**After:**

```dart
void main() async {
  final logger = Logger(LoggerConfig.debug());
  await logger.init();
  logger.info('APP', 'Application started');
}
```

## [0.1.0-beta.2] - 2025-10-12

### Added

- added stackTrace and error parameters to the log methods

## [0.1.0-beta.1] - 2025-10-12

### Added

- chore: xsoulspace_lints 0.1.2
- Initial beta release.
- Basic logger with multiple log levels: VERBOSE, DEBUG, INFO, WARNING, ERROR.
- Console and file configurable outputs.
- Async file writes with buffering and log rotation (time and size-based).
- Structured logging with optional data maps.
- Several configuration presets (debug, production, verbose, silent, console only).
- Example usage in documentation.
