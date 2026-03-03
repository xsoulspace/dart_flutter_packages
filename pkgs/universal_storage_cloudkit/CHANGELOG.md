# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0-dev.1 - 2026-03-03

- Initial CloudKit provider package.
- Added `CloudKitStorageProvider` with `remoteOnly` and `localMirror` modes.
- Added fallback provider delegation for unsupported/failed CloudKit init.
- Added `registerUniversalStorageCloudKit()` helper for provider registry wiring.
- Fixed local-mirror conflict behavior for `clientAlwaysRight` and
  `lastWriteWins` to force expected push reconciliation.
- Added safer mirror-state persistence fallback (no delete-before-rename).
- Auto-registers web bridge in `registerUniversalStorageCloudKit()` when
  running on web and no explicit bridge is provided.
- Replaced runtime dependency on `universal_storage_filesystem` with internal
  local mirror store implementation to keep CloudKit runtime dependency graph
  Dart-only.
