<!--
version: 1.0.0
repository: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_review
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Usage Guide for xsoulspace_review

This document provides a guide for an AI agent on how to use the features of the `xsoulspace_review` library within a project.

## Core Components

- `ReviewFoundation`: The central container and entry point for all review and feedback operations.
- `StoreReviewRequester`: Manages the logic for when to prompt the user for a review.
- `UserFeedback`: Handles user feedback collection, primarily through Wiredash.

## Common Tasks

### Task 1: Manually Requesting a Store Review

This is the most common use case, typically triggered by a "Rate Us" button.

**Agent Action:**

1.  Ensure `ReviewFoundation` has been initialized and is accessible.
2.  Get the current `BuildContext`.
3.  Call `reviewFoundation.requestReview(context)`. The library will handle the logic of whether to show the prompt based on the `StoreReviewRequester`'s configuration.

**Example Implementation in a Flutter Widget:**

```dart
import 'package:flutter/material.dart';
// Assuming reviewFoundation is a global or accessed via DI
import 'path/to/main.dart';

class RateUsButton extends StatelessWidget {
  const RateUsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        // This call is safe; the library decides if a prompt is needed.
        reviewFoundation.requestReview(context);
      },
      child: const Text('Rate Our App'),
    );
  }
}
```

### Task 2: Showing the User Feedback Form

This task is used to programmatically open the Wiredash feedback form.

**Agent Action:**

1.  Ensure the `UserFeedback.wiredash` widget is wrapping the `MaterialApp`.
2.  Get the current `BuildContext`.
3.  Call `UserFeedback.show(context)`.

**Example Implementation:**

```dart
import 'package:flutter/material.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        UserFeedback.show(context);
      },
      child: const Text('Send Feedback'),
    );
  }
}
```

### Task 3: Modifying the Review Schedule

If the user wants to change how often review prompts are shown.

**Agent Action:**

1.  Locate the instantiation of `StoreReviewRequester`.
2.  Modify the constructor parameters: `firstReviewPeriod`, `reviewPeriod`, or `maxReviewCount`.

**Example Modification:**

```dart
// Before: First review after 3 days, then every 30 days.
final requester = StoreReviewRequester(
  localDb: localDb,
  firstReviewPeriod: const Duration(days: 3),
  reviewPeriod: const Duration(days: 30),
  maxReviewCount: 3,
);

// After: First review after 7 days, then every 60 days.
final requester = StoreReviewRequester(
  localDb: localDb,
  firstReviewPeriod: const Duration(days: 7),
  reviewPeriod: const Duration(days: 60),
  maxReviewCount: 3,
);
```

### Task 4: Implementing a Custom Consent Dialog

For app stores that do not have a native review prompt (like RuStore or Snap Store), you might need to use a custom consent dialog.

**Agent Action:**

1.  Create a function that matches the `ConsentBuilder` typedef: `Future<bool> Function(BuildContext, Locale)`.
2.  This function should display a custom dialog (e.g., using `showDialog`) asking for the user's consent to be redirected to the store page.
3.  It must return `true` if the user consents, and `false` otherwise.
4.  Pass this function to the `consentBuilder` parameter of the relevant `StoreReviewer`'s constructor.

**Example:**

```dart
// 1. Define the custom builder function
Future<bool> myCustomConsentBuilder(BuildContext context, Locale locale) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Rate our App?'),
        content: const Text('You will be redirected to the store to leave a review.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

// 2. Pass it to the reviewer's constructor
final reviewer = RuStoreReviewer(
  packageName: 'com.example.app',
  consentBuilder: myCustomConsentBuilder,
);
```
