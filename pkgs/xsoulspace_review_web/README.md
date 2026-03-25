# xsoulspace_review_web

Web review implementation for xsoulspace_review.

## Production readiness

- Supported platforms: Web as a safe no-op reviewer fallback.
- Known limitations:
  - The current reviewer intentionally does not open external rating services.
  - Applications should provide their own web feedback or rating surface when needed.
- Required configuration:
  - Register `WebStoreReviewer` in your review provider composition for web targets.
  - Route users to your preferred feedback destination from app UI if review capture is required.
- Rollback guidance:
  - Replace `WebStoreReviewer` with your previous web reviewer binding.
  - Validate review flow wiring in `ReviewFoundation` after the swap.

## Usage

```dart
import 'package:xsoulspace_review_web/xsoulspace_review_web.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Create the reviewer
final reviewer = WebStoreReviewer();

// Use with ReviewFoundation
final foundation = ReviewFoundation(
  storeReviewer: reviewer,
  requester: StoreReviewRequester(localDb: yourLocalDb),
);

await foundation.init();
```

## Platform Support

- ✅ Web - no-op fallback implementation

## Future Plans

Possible implementations could include:

- Custom review form
- Integration with third-party review platforms
- Custom feedback collection

## Contributing

Contributions to add web review functionality are welcome!

## Related Packages

- `xsoulspace_review_interface` - Base abstractions
- `xsoulspace_review` - Core orchestration
