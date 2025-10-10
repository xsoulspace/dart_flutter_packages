# xsoulspace_review_snapstore

Linux Snap Store review implementation for xsoulspace_review.

## Features

- Opens Snap Store review page via snap:// scheme
- Consent dialog before opening store
- Linux platform support

## Usage

```dart
import 'package:xsoulspace_review_snapstore/xsoulspace_review_snapstore.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Create the reviewer with consent builder
final reviewer = SnapStoreReviewer(
  packageName: 'your-snap-package-name',
  consentBuilder: defaultFallbackConsentBuilder,
);

// Use with ReviewFoundation
final foundation = ReviewFoundation(
  storeReviewer: reviewer,
  requester: StoreReviewRequester(localDb: yourLocalDb),
);

await foundation.init();
```

## Platform Support

- ✅ Linux (Snap Store)

## Note

The package name should be your Snap package name, not the Android package name.

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration (provides `defaultFallbackConsentBuilder`)
