## Unreleased

### Breaking changes

- **Sync semantics changed**: `sync()` now throws
  `UnsupportedOperationException` instead of silently no-oping; local_db is
  a local-only backend.

## 0.1.0-dev.1

- Add `LocalDbStorageProvider` implementing `StorageProvider` + `LocalEngine`.
- Add `LocalDbStorageConfig` with keyspace prefixing support.
- Add provider unit tests for CRUD, listing, and keyspace isolation.
