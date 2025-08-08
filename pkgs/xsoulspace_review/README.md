# xsoulspace_review Package

The main purpose of this package is to unite and simplify the process of requesting reviews from various stores.

Currently, the package supports the following stores:

## Supported Stores

### Native Support

- **Google Play and App Store** - Uses [in_app_review](https://pub.dev/packages/in_app_review) for native in-app review dialogs
- **RuStore** - Russian app store with native review functionality

### Non-Native Support

- **Snapstore** - Uses consent screen followed by store redirection

## Usage

### Basic Usage

```dart
import 'package:xsoulspace_review/xsoulspace_review.dart';

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
```

Or if you want to create a store reviewer based on the installation source (temporary disabled):

```dart
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

## Features

- **Cross-platform support** for multiple app stores
- **Automatic store detection** based on installation source
- **Native in-app review dialogs** where supported
- **Fallback mechanisms** for stores without native review support
- **Configurable review scheduling** and timing
