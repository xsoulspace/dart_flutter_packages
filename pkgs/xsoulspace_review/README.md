# xsoulspace_review

Foundation package for xsoulspace_review with core orchestration and UI components.

## Features

- **ReviewFoundation**: Container class following dependency injection pattern
- **StoreReviewRequester**: Automatic review scheduling with configurable periods
- **User Feedback**: Wiredash integration for collecting user feedback
- **Consent Dialogs**: Multilingual consent screens for review requests
- **defaultFallbackConsentBuilder**: Pre-built consent dialog for stores without native prompts

## Architecture

This package follows the **container principle** similar to `MonetizationFoundation`:

- Accepts `StoreReviewer` implementations via dependency injection
- No factory pattern - apps compose their own store reviewer
- Prevents SDK conflicts by keeping implementations separate

## Usage

### Basic Setup

```dart
import 'package:xsoulspace_review/xsoulspace_review.dart';
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';

// 1. Create store-specific reviewer
final storeReviewer = GoogleAppleStoreReviewer();

// 2. Create requester with local database
final requester = StoreReviewRequester(
  localDb: yourLocalDbImplementation,
  firstReviewPeriod: Duration(days: 3),
  reviewPeriod: Duration(days: 30),
  maxReviewCount: 3,
);

// 3. Create foundation container
final reviewFoundation = ReviewFoundation(
  storeReviewer: storeReviewer,
  requester: requester,
);

// 4. Initialize
await reviewFoundation.init();
```

### Manual Review Request

```dart
// User clicks "Rate Us" button
ElevatedButton(
  onPressed: () => reviewFoundation.requestReview(context),
  child: Text('Rate Us'),
);
```

### User Feedback (Wiredash)

```dart
UserFeedback.wiredash(
  dto: UserFeedbackWiredashDto(
    projectId: 'your-wiredash-project-id',
    secret: 'your-wiredash-secret',
  ),
  child: MaterialApp(
    // ... your app
  ),
);

// Show feedback form
UserFeedback.show(context);
```

### Platform-Specific Configuration

**For Google Play / App Store:**

```dart
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';

final reviewer = GoogleAppleStoreReviewer();
```

**For RuStore:**

```dart
import 'package:xsoulspace_review_rustore/xsoulspace_review_rustore.dart';

final reviewer = RuStoreReviewer(
  packageName: 'com.example.app',
  consentBuilder: defaultFallbackConsentBuilder,
);
```

**For Snap Store:**

```dart
import 'package:xsoulspace_review_snapstore/xsoulspace_review_snapstore.dart';

final reviewer = SnapStoreReviewer(
  packageName: 'your-snap-name',
  consentBuilder: defaultFallbackConsentBuilder,
);
```

## Configuration

### Review Scheduling

Configure how often review prompts appear:

```dart
StoreReviewRequester(
  localDb: yourLocalDb,
  firstReviewPeriod: Duration(days: 1),  // After 1 day
  reviewPeriod: Duration(days: 30),       // Every 30 days after
  maxReviewCount: 3,                       // Max 3 times total
);
```

### Custom Consent Dialog

Create your own consent builder:

```dart
Future<bool> myCustomConsentBuilder(
  BuildContext context,
  Locale locale,
) async {
  // Show your custom dialog
  return true; // or false based on user choice
}

final reviewer = RuStoreReviewer(
  packageName: 'com.example.app',
  consentBuilder: myCustomConsentBuilder,
);
```

## Container Pattern Benefits

1. **No SDK Conflicts**: Each build only includes the store SDK it needs
2. **Flexible Composition**: Apps choose their own reviewer implementation
3. **Easy Testing**: Mock `StoreReviewer` for unit tests
4. **Clean Dependencies**: No circular dependencies or factory complexity

## Related Packages

### Store Implementations

- `xsoulspace_review_google_apple` - Google Play & Apple App Store
- `xsoulspace_review_rustore` - RuStore
- `xsoulspace_review_huawei` - Huawei AppGallery
- `xsoulspace_review_snapstore` - Linux Snap Store
- `xsoulspace_review_web` - Web platforms

### Interface

- `xsoulspace_review_interface` - Base abstractions

## Logging (Optional)

The package supports optional integration with `xsoulspace_logger` for debugging and monitoring. Logging is completely optional - the library works perfectly without it.

### Why Optional?

Pass a logger instance only when you need debugging or monitoring capabilities. When not provided, there's zero overhead.

### Basic Usage

```dart
import 'package:flutter/foundation.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

// Initialize logger in your app
final logger = Logger(
  kDebugMode
      ? LoggerConfig.debug()
      : LoggerConfig.production(),
);
await logger.init();

// Pass logger to components
final requester = StoreReviewRequester(
  localDb: yourLocalDb,
  logger: logger, // Optional
);

final reviewFoundation = ReviewFoundation(
  storeReviewer: storeReviewer,
  requester: requester,
  logger: logger, // Optional
);
```

### Configuration Presets

Use `ReviewLoggerConfig` for environment-aware presets:

```dart
// Debug mode: verbose logging, console + file
final debugConfig = ReviewLoggerConfig.getConfig(isDebugMode: true);

// Production: info level, optional file logging
final prodConfig = ReviewLoggerConfig.getConfig(
  isDebugMode: false,
  enableFileLogging: true,
);

// Testing: console only, warnings and above
final testConfig = ReviewLoggerConfig.testing;
```

### Log Categories

When logger is provided, these categories are used:

- `REVIEW` - Store review operations
- `FEEDBACK` - User feedback operations
- `CONSENT` - User consent management

### Benefits

- **Development**: Detailed debugging information
- **Production**: Monitor review flow and issues
- **Testing**: Track user interactions
- **Optional**: No overhead when not used

## Migration from Old xsoulspace_review

See [MIGRATION.md](MIGRATION.md) for detailed migration guide.

Quick changes:

1. Replace `StoreReviewerFactory.createForTargetStore()` with direct instantiation
2. Create `ReviewFoundation` container
3. Update dependencies to use store-specific packages
