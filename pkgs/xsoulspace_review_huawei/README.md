# xsoulspace_review_huawei

Huawei AppGallery review implementation for xsoulspace_review.

## Status

⚠️ **Work in Progress**: This package currently contains a placeholder implementation pending Huawei AppGallery review API integration.

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

- 🚧 Android (Huawei AppGallery) - Implementation pending

## Contributing

Contributions to add Huawei AppGallery review functionality are welcome!

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration
