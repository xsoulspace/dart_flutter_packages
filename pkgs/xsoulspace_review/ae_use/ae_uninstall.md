<!--
version: 1.0.0
repository: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_review
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Uninstallation Guide for xsoulspace_review

This document provides instructions for an AI agent to completely and safely uninstall the `xsoulspace_review` library from a project.

## 1. Code Removal

### 1.1. Remove `ReviewFoundation` Initialization

Locate the initialization of `ReviewFoundation` (usually in `main.dart` or a dependency injection setup file) and remove the entire block of code related to it.

**Agent Action:**

- Find and delete the code that instantiates `GoogleAppleStoreReviewer` (or any other `StoreReviewer`), `StoreReviewRequester`, your `IReviewLocalDb` implementation, and `ReviewFoundation`.
- Remove the call to `reviewFoundation.init()`.

**Example Code to Remove:**

```dart
// main.dart or in your DI setup

// DELETE THIS BLOCK
// Global instance or provided via DI
late final ReviewFoundation reviewFoundation;

// ... inside main()

// DELETE THIS BLOCK
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
```

### 1.2. Remove `IReviewLocalDb` Implementation

Delete the file containing your implementation of `IReviewLocalDb` (e.g., `shared_preferences_review_db.dart`).

### 1.3. Remove `UserFeedback.wiredash` Wrapper (if used)

If `UserFeedback.wiredash` was used, remove the widget wrapper from your root `MaterialApp`.

**Before:**

```dart
runApp(
  UserFeedback.wiredash(
    dto: UserFeedbackWiredashDto(...),
    child: const MyApp(),
  ),
);
```

**After:**

```dart
runApp(const MyApp());
```

### 1.4. Remove All Calls to `reviewFoundation` and `UserFeedback`

Search the codebase for any calls to:

- `reviewFoundation.requestReview(context)`
- `UserFeedback.show(context)`

Remove these calls and any associated UI elements (e.g., "Rate Us" buttons).

### 1.5. Remove Imports

Clean up all unused imports related to `xsoulspace_review` and its associated packages from the modified files.

## 2. Dependency Removal

### 2.1. Update `pubspec.yaml`

Remove the following packages from the `dependencies` section of your `pubspec.yaml` file:

- `xsoulspace_review`
- The store-specific reviewer package (e.g., `xsoulspace_review_google_apple`)
- `wiredash` (if it was only used for this library)
- `shared_preferences` (if it was only used for the `IReviewLocalDb` implementation)

### 2.2. Run `pub get`

Execute `flutter pub get` in the terminal to remove the dependencies from your project.

## 3. Validation

To validate the uninstallation, perform the following checks:

1.  The app compiles and runs without any errors.
2.  A global search for `xsoulspace_review`, `ReviewFoundation`, and the specific `StoreReviewer` used should yield no results in the codebase (apart from `pubspec.lock`).
3.  Verify that all related UI elements (like "Rate Us" buttons) have been removed.
