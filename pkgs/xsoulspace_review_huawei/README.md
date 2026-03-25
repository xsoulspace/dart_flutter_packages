# xsoulspace_review_huawei

Huawei AppGallery review implementation for xsoulspace_review.

## Production readiness

- Supported platforms: Android (Huawei AppGallery) as a safe no-op reviewer fallback.
- Known limitations:
  - The current reviewer intentionally performs no native review prompt call.
  - Use this package when you need a stable interface implementation while Huawei review API strategy is finalized.
- Required configuration:
  - Wire this reviewer through `ReviewFoundation` for Huawei builds.
  - Provide user-facing fallback UX (for example custom feedback flow) if direct store review is required.
- Rollback guidance:
  - Swap to your previous reviewer implementation in dependency injection.
  - Keep `xsoulspace_review_interface` contract unchanged to avoid app-level migration work.

## Usage

```dart
import 'package:xsoulspace_review_huawei/xsoulspace_review_huawei.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Create the reviewer
final reviewer = HuaweiStoreReviewer();

// Use with ReviewFoundation
final foundation = ReviewFoundation(
  storeReviewer: reviewer,
  requester: StoreReviewRequester(localDb: yourLocalDb),
);

await foundation.init();
```

## Platform Support

- ✅ Android (Huawei AppGallery) - no-op fallback implementation

## Contributing

Contributions to add Huawei AppGallery review functionality are welcome!

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration
