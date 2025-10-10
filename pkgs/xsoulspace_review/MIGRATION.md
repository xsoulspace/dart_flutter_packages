# Migration Guide: xsoulspace_review v0.3.x → v0.1.x (New Architecture)

This guide helps you migrate from the old monolithic `xsoulspace_review` package to the new modular architecture following the container/dependency injection pattern.

## Overview of Changes

### Old Architecture

```
xsoulspace_review/
  ├── StoreReviewerFactory (creates reviewers based on enum)
  ├── All store implementations in one package
  └── All SDKs included in every build
```

### New Architecture

```
xsoulspace_review_interface/         # Base abstractions
xsoulspace_review/        # Core + UI
xsoulspace_review_google_apple/      # Google/Apple only
xsoulspace_review_rustore/           # RuStore only
xsoulspace_review_huawei/            # Huawei only
xsoulspace_review_snapstore/         # Snap only
xsoulspace_review_web/               # Web only
```

## Key Benefits

1. **No SDK Conflicts**: Only include store SDKs you actually use
2. **Smaller Builds**: Don't ship unused store implementations
3. **Container Pattern**: Following same pattern as `MonetizationFoundation`
4. **Better Testing**: Easy to mock `StoreReviewer` implementations

## Step-by-Step Migration

### 1. Update Dependencies

**Old `pubspec.yaml`:**

```yaml
dependencies:
  xsoulspace_review: ^0.3.0
```

**New `pubspec.yaml`:**

```yaml
dependencies:
  # Core foundation (always needed)
  xsoulspace_review: ^0.1.0

  # Only add the stores you target
  xsoulspace_review_google_apple: ^0.1.0 # For Google Play / App Store
  # xsoulspace_review_rustore: ^0.1.0     # For RuStore
  # xsoulspace_review_huawei: ^0.1.0      # For Huawei
  # xsoulspace_review_snapstore: ^0.1.0   # For Snap Store
  # xsoulspace_review_web: ^0.1.0         # For Web
```

### 2. Update Imports

**Old:**

```dart
import 'package:xsoulspace_review/xsoulspace_review.dart';
```

**New:**

```dart
import 'package:xsoulspace_review/xsoulspace_review.dart';
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';
```

### 3. Replace Factory with Direct Instantiation

#### Option A: Using Target Store (Compile-Time)

**Old:**

```dart
final storeReviewer = StoreReviewerFactory.createForTargetStore(
  targetStore: InstallationTargetStore.mobileGooglePlay,
  androidPackageName: 'com.example.app',
  fallbackConsentBuilder: defaultFallbackConsentBuilder,
);

final requester = StoreReviewRequester(
  storeReviewer: storeReviewer,
  localDb: myLocalDb,
);

await requester.onLoad();
```

**New:**

```dart
// Directly instantiate the reviewer you need for this build
final storeReviewer = GoogleAppleStoreReviewer();

final requester = StoreReviewRequester(
  localDb: myLocalDb,
);

final foundation = ReviewFoundation(
  storeReviewer: storeReviewer,
  requester: requester,
);

await foundation.init();
```

#### Option B: Runtime Detection (if needed)

**Old:**

```dart
final storeReviewer = await StoreReviewerFactory.createForInstallSource(
  androidPackageName: 'com.example.app',
  snapPackageName: 'my-snap',
  fallbackConsentBuilder: defaultFallbackConsentBuilder,
);

final requester = StoreReviewRequester(
  storeReviewer: storeReviewer,
  localDb: myLocalDb,
);

await requester.onLoad();
```

**New:**

```dart
// Create your own runtime detection based on platform
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

Future<StoreReviewer> createStoreReviewer() async {
  final installSource = await const InstallationStoreUtils()
      .getInstallationSource();

  return switch (installSource) {
    InstallationStoreSource.androidRuStore => RuStoreReviewer(
      consentBuilder: defaultFallbackConsentBuilder,
      packageName: 'com.example.app',
    ),
    InstallationStoreSource.androidHuaweiAppGallery => HuaweiStoreReviewer(),
    InstallationStoreSource.androidGooglePlay ||
    _ when installSource.isApple => GoogleAppleStoreReviewer(),
    InstallationStoreSource.linuxSnap => SnapStoreReviewer(
      packageName: 'my-snap',
      consentBuilder: defaultFallbackConsentBuilder,
    ),
    _ => WebStoreReviewer(),
  };
}

// Usage
final storeReviewer = await createStoreReviewer();
final requester = StoreReviewRequester(localDb: myLocalDb);
final foundation = ReviewFoundation(
  storeReviewer: storeReviewer,
  requester: requester,
);

await foundation.init();
```

### 4. Update Review Requests

**Old:**

```dart
await requester.requestReview(
  context: context,
  locale: locale,
);
```

**New:**

```dart
await foundation.requestReview(
  context,
  locale: locale,
);
```

### 5. User Feedback (No Change)

User feedback API remains the same:

```dart
UserFeedback.wiredash(
  dto: UserFeedbackWiredashDto(
    projectId: 'your-project-id',
    secret: 'your-secret',
  ),
  child: MyApp(),
);

// Show feedback
UserFeedback.show(context);
```

## Platform-Specific Examples

### Google Play / App Store Only

```dart
// pubspec.yaml
dependencies:
  xsoulspace_review: ^0.1.0
  xsoulspace_review_google_apple: ^0.1.0

// main.dart
final foundation = ReviewFoundation(
  storeReviewer: GoogleAppleStoreReviewer(),
  requester: StoreReviewRequester(localDb: myLocalDb),
);
```

### RuStore Build

```dart
// pubspec.yaml
dependencies:
  xsoulspace_review: ^0.1.0
  xsoulspace_review_rustore: ^0.1.0

// main.dart
final foundation = ReviewFoundation(
  storeReviewer: RuStoreReviewer(
    packageName: 'com.example.app',
    consentBuilder: defaultFallbackConsentBuilder,
  ),
  requester: StoreReviewRequester(localDb: myLocalDb),
);
```

### Multi-Store App (Runtime Detection)

```dart
// pubspec.yaml
dependencies:
  xsoulspace_review: ^0.1.0
  xsoulspace_review_google_apple: ^0.1.0
  xsoulspace_review_rustore: ^0.1.0
  xsoulspace_installation_store: ^0.1.2

// Create factory helper
Future<StoreReviewer> createReviewerForCurrentStore() async {
  final source = await const InstallationStoreUtils()
      .getInstallationSource();

  if (source == InstallationStoreSource.androidRuStore) {
    return RuStoreReviewer(
      packageName: 'com.example.app',
      consentBuilder: defaultFallbackConsentBuilder,
    );
  }
  return GoogleAppleStoreReviewer();
}
```

## Breaking Changes Summary

| Old                                             | New                                               |
| ----------------------------------------------- | ------------------------------------------------- |
| `StoreReviewerFactory.createForTargetStore()`   | Direct instantiation of store reviewer            |
| `StoreReviewerFactory.createForInstallSource()` | Create your own runtime detection                 |
| Single package dependency                       | Modular packages (interface + foundation + store) |
| Factory injects reviewer into requester         | Container accepts reviewer via DI                 |
| `requester.requestReview()`                     | `foundation.requestReview()`                      |

## Testing

**Old:**

```dart
final mockReviewer = MockStoreReviewer();
final requester = StoreReviewRequester(
  storeReviewer: mockReviewer,
  localDb: mockLocalDb,
);
```

**New:**

```dart
final mockReviewer = MockStoreReviewer();
final foundation = ReviewFoundation(
  storeReviewer: mockReviewer,
  requester: StoreReviewRequester(localDb: mockLocalDb),
);
```

Same mocking capability, cleaner container pattern!

## Common Issues

### Issue: "Can't find StoreReviewerFactory"

**Solution**: Remove factory usage, directly instantiate the reviewer you need.

### Issue: "Too many dependencies"

**Solution**: Only add store packages you actually use. Most apps only need one.

### Issue: "How do I detect store at runtime?"

**Solution**: See "Option B: Runtime Detection" above. Create your own switch based on `xsoulspace_installation_store`.

### Issue: "Consent builder not found"

**Solution**: Import from foundation: `import 'package:xsoulspace_review/xsoulspace_review.dart';`

## Need Help?

- Open an issue: https://github.com/xsoulspace/xsoulspace_packages/issues
- Check examples in each package's README
- Review `xsoulspace_monetization` packages for similar pattern
