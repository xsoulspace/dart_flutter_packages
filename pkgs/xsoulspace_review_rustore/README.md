# xsoulspace_review_rustore

RuStore review implementation for xsoulspace_review.

## Features

- Native in-app review prompts for RuStore
- Fallback to browser when review limit is reached
- Uses the `flutter_rustore_review` package

## Usage

```dart
import 'package:xsoulspace_review_rustore/xsoulspace_review_rustore.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Create the reviewer with consent builder
final reviewer = RuStoreReviewer(
  packageName: 'com.example.app',
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

- ✅ Android (RuStore)

## Special Features

- Handles `RuStoreRequestLimitReached` exception with fallback to browser
- Handles `RuStoreReviewExists` exception gracefully

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration (provides `defaultFallbackConsentBuilder`)
