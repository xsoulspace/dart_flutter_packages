<!--
version: 1.0.0
repository: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_review
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Installation Guide for xsoulspace_review

This document provides instructions for an AI agent to install, configure, and integrate the `xsoulspace_review` library.

## 1. Installation

### 1.1. Add Dependencies

Add `xsoulspace_review` and the required store-specific implementation to `pubspec.yaml`.

**Example for Google Play & App Store:**

```yaml
dependencies:
  xsoulspace_review: ^0.4.0-beta.1
  xsoulspace_review_google_apple: ^0.1.0 # Use the latest version
```

**Example for RuStore:**

```yaml
dependencies:
  xsoulspace_review: ^0.4.0-beta.1
  xsoulspace_review_rustore: ^0.1.0 # Use the latest version
```

> **Note**: Choose only one store-specific package per build target. A list of available reviewers can be found in the library's `README.md`.

### 1.2. Run `pub get`

Execute `flutter pub get` in the terminal to fetch the dependencies.

## 2. Configuration

### 2.1. Implement Local Database for `StoreReviewRequester`

The `StoreReviewRequester` requires a `localDb` that implements `IReviewLocalDb`. This is used to persist review request timestamps and counters.

**Abstract Interface (`IReviewLocalDb` from `xsoulspace_review_interface`):**

```dart
abstract interface class IReviewLocalDb {
  Future<int> getReviewCount();
  Future<void> saveReviewCount(int count);
  Future<DateTime?> getLastReviewDate();
  Future<void> saveLastReviewDate(DateTime date);
}
```

**Agent Action:**

1. Check if the user's project has an existing local database solution (e.g., Hive, SharedPreferences, Drift).
2. If it does, create an adapter class that implements `IReviewLocalDb`.
3. If not, ask the user which simple key-value store they prefer (e.g., `shared_preferences`) and implement `IReviewLocalDb` using it.

**Example Implementation with `shared_preferences`:**

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

class SharedPreferencesReviewDb implements IReviewLocalDb {
  const SharedPreferencesReviewDb(this._prefs);

  final SharedPreferences _prefs;
  static const _reviewCountKey = 'review_count';
  static const _lastReviewDateKey = 'last_review_date';

  @override
  Future<int> getReviewCount() async => _prefs.getInt(_reviewCountKey) ?? 0;

  @override
  Future<void> saveReviewCount(int count) async =>
      _prefs.setInt(_reviewCountKey, count);

  @override
  Future<DateTime?> getLastReviewDate() async {
    final dateString = _prefs.getString(_lastReviewDateKey);
    return dateString != null ? DateTime.tryParse(dateString) : null;
  }

  @override
  Future<void> saveLastReviewDate(DateTime date) async =>
      _prefs.setString(_lastReviewDateKey, date.toIso8601String());
}
```

## 3. Integration

### 3.1. Initialize `ReviewFoundation`

The core of the library is the `ReviewFoundation` container. It should be initialized and made available in the application, for example, through a dependency injection framework like `provider` or `get_it`.

**Steps:**

1.  Instantiate the platform-specific `StoreReviewer`.
2.  Instantiate your `IReviewLocalDb` implementation.
3.  Instantiate `StoreReviewRequester` with the database implementation and desired scheduling configuration.
4.  Instantiate `ReviewFoundation`.
5.  Call `reviewFoundation.init()` early in your app's lifecycle (e.g., in `main()`).

**Example `main.dart` Integration:**

```dart
// main.dart or in your DI setup
import 'package:flutter/material.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';
// Import your chosen store reviewer
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';
// Import your IReviewLocalDb implementation
import 'path/to/shared_preferences_review_db.dart';
import 'package:shared_preferences/shared_preferences.dart';


// Global instance or provided via DI
late final ReviewFoundation reviewFoundation;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Create store-specific reviewer
  final storeReviewer = GoogleAppleStoreReviewer();

  // 2. Create requester with local database
  final prefs = await SharedPreferences.getInstance();
  final localDb = SharedPreferencesReviewDb(prefs);

  final requester = StoreReviewRequester(
    localDb: localDb,
    firstReviewPeriod: const Duration(days: 3),
    reviewPeriod: const Duration(days: 30),
    maxReviewCount: 3,
  );

  // 3. Create foundation container
  reviewFoundation = ReviewFoundation(
    storeReviewer: storeReviewer,
    requester: requester,
  );

  // 4. Initialize
  await reviewFoundation.init();

  runApp(const MyApp());
}
```

### 3.2. Optional: Configure User Feedback with Wiredash

If the user wants to collect user feedback, integrate `UserFeedback.wiredash`.

**Steps:**

1. Add `wiredash: ^2.5.0` to `pubspec.yaml` if not already present.
2. Wrap the root `MaterialApp` widget with `UserFeedback.wiredash`.
3. Provide the `projectId` and `secret` from Wiredash.

**Example:**

```dart
// main.dart
runApp(
  UserFeedback.wiredash(
    dto: UserFeedbackWiredashDto(
      projectId: 'your-wiredash-project-id',
      secret: 'your-wiredash-secret',
    ),
    child: const MyApp(),
  ),
);

// To show the feedback form from anywhere:
// UserFeedback.show(context);
```

## 4. Validation

To validate the installation, perform the following checks:

1.  The app compiles and runs without errors.
2.  A call to `reviewFoundation.requestReview(context)` triggers the native review prompt (on supported platforms) or the fallback consent dialog.
3.  Confirm that after a review is requested, the `review_count` and `last_review_date` are updated in the local database.
