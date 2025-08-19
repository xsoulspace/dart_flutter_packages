# Changelog

## 0.3.0-beta.5

- chore: xsoulspace_lints 0.1.2
- chore: xsoulspace_foundation 0.2.1
- chore: xsoulspace_installation_store 0.1.2
- chore: xsoulspace_locale 0.3.2

## 0.3.0-beta.4

- Added `androidPackageName` to `createForTargetStore`.

## 0.3.0-beta.3

- changed method to initialize `StoreReviewer`:

```dart
final myStoreReviewer = StoreReviewerFactory.createForTargetStore(
  targetStore: InstallationTargetStore.mobileGooglePlay,
);
final reviewRequester = StoreReviewRequester(
  firstReviewPeriod: Duration(days: 1),
  reviewPeriod: Duration(days: 30),
  maxReviewCount: 3,
  storeReviewer: myStoreReviewer,
  localDb: myLocalDb,
);
await reviewRequester.onLoad();
// or
final reviewRequester = StoreReviewRequester(
  firstReviewPeriod: Duration(days: 1),
  reviewPeriod: Duration(days: 30),
  maxReviewCount: 3,
  localDb: myLocalDb,
);
final myStoreReviewer = await StoreReviewerFactory.createForInstallSource();
await reviewRequester.onLoad(
  storeReviewer: myStoreReviewer,
);
```

## 0.3.0-beta.2

- silent review assignment during onLoad.

## 0.3.0-beta.1

- Temporary disabled detection of install source to exclude store checker so `createForInstallSource` is not working. Use `createForTargetStore` instead.
- Renamed `create` to `createForInstallSource`.
- Added `InstallationTargetStore`.

## 0.2.1

- Updated:
  - flutter_rustore_review: ^9.0.2
  - wiredash: ^2.5.0
  - lints: ^6.0.0

## 0.2.0

- chore: sdk: ">=3.8.1 <4.0.0"

## 0.1.1

- Updated:
  - sdk: ">=3.7.0 <4.0.0"
  - wiredash: ^2.4.0
  - xsoulspace_foundation: ^0.0.10
  - lints: ^5.1.1
  - xsoulspace_lints: ^0.0.14

## 0.1.0

- Initial release with basic stores and main logic.
