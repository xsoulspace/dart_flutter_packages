# xsoulspace_review_interface

Common interfaces for xsoulspace_review packages.

## Overview

This package provides the base abstractions for implementing store review functionality across different platforms and stores.

## Core Types

### StoreReviewer

Base class that defines the contract for all store reviewer implementations:

```dart
abstract class StoreReviewer {
  Future<bool> onLoad();
  Future<void> requestReview(BuildContext context, {Locale? locale, bool force = false});
}
```

### ReviewerFallbackConsentBuilder

Typedef for building custom consent dialogs:

```dart
typedef ReviewerFallbackConsentBuilder = Future<bool> Function(
  BuildContext context,
  Locale locale
);
```

## Usage

This package is typically used as a dependency by:

- Store-specific implementation packages (e.g., `xsoulspace_review_google_apple`)
- The foundation package (`xsoulspace_review`)

You don't usually depend on this package directly in your app.

## Related Packages

- `xsoulspace_review` - Core orchestration and UI
- `xsoulspace_review_google_apple` - Google Play & App Store implementation
- `xsoulspace_review_rustore` - RuStore implementation
- `xsoulspace_review_huawei` - Huawei AppGallery implementation
