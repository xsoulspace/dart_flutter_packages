## 0.2.0

- **BREAKING**: `InstallationTargetStore` is no longer a closed enum — it is
  now an alias of `oka_store`'s open `StoreKey` (a validated string extension
  type). A new store is a new key value composed by the project, never a PR
  here. Migration: `InstallationTargetStore.mobileGooglePlay` →
  `installationTargetGooglePlay` (aka `storeKeyGooglePlay`), `.rustore` →
  `installationTargetRuStore`, `.mobileAppleAppStore` →
  `installationTargetAppleAppStore`, `.huawei` → `installationTargetHuawei`
  (the AppGallery key); the enum's `name` field is the key itself.
- Adds the display-only `InstallationTargetStoreLabel` extension.
- **Publish note**: requires `oka_store` (oka repo) on pub.dev before this
  version publishes; local development uses `pubspec_overrides.yaml`.
