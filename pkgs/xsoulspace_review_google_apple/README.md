# xsoulspace_review_google_apple

Google Play and Apple App Store review implementation for xsoulspace_review.

## Features

- Native in-app review prompts for Android (Google Play)
- Native in-app review prompts for iOS (App Store)
- Uses the `in_app_review` package

## Usage

```dart
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Create the reviewer
final reviewer = GoogleAppleStoreReviewer();

// Use with ReviewFoundation
final foundation = ReviewFoundation(
  storeReviewer: reviewer,
  requester: StoreReviewRequester(localDb: yourLocalDb),
);

await foundation.init();
```

## Platform Support

- ✅ Android (Google Play)
- ✅ iOS (App Store)

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration
