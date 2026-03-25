# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0-dev.1 - 2026-03-03

- Initial Apple CloudKit bridge package.
- Added typed Pigeon bridge implementation and registration helper.
- Implemented iOS/macOS CloudKit private-database operations:
  zone bootstrap, CRUD, prefix query, zone-change fetch, and token
  encode/decode.
- Added CKError to bridge-error code mapping for auth/network/conflict/not-found.
- Added persistent recordName-to-path cache for deletion path reconstruction in
  zone deltas.
- Refactored token codec + CKError mapping into shared Apple support utilities.
- Added Swift unit tests (SwiftPM) for token codec validation and CKError
  mapping behavior, including partial-failure nested error handling.
