# Changelog

All notable changes to this package will be documented in this file.

## 1.0.0-beta.0

- Initial beta release.
- Added `UniversalStorageSink` adapter over `StorageService`.
- Added append NDJSON persistence and periodic snapshot compaction.
- Added snapshot restore API hook.
- Added tests for append ordering, compaction, and sequence recovery.
