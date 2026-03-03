# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0-dev.1 - 2026-03-03

- Initial CloudKit provider package.
- Added `CloudKitStorageProvider` with `remoteOnly` and `localMirror` modes.
- Added fallback provider delegation for unsupported/failed CloudKit init.
- Added `registerUniversalStorageCloudKit()` helper for provider registry wiring.
