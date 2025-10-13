<!--
version: 1.0.0
repository: https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_review
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Update Guide for xsoulspace_review

This document provides instructions for an AI agent to update the `xsoulspace_review` library to a new version.

## 1. Pre-Update Analysis

### 1.1. Check for Breaking Changes

Before performing the update, the agent must check the `CHANGELOG.md` of `xsoulspace_review` and any relevant store-specific packages (e.g., `xsoulspace_review_google_apple`) for breaking changes between the current and target versions.

**Agent Action:**

1.  Identify the current version of `xsoulspace_review` in the user's `pubspec.yaml`.
2.  Determine the latest available version to update to.
3.  Fetch and parse the `CHANGELOG.md` from the library's repository.
4.  Identify any entries marked as "BREAKING" or major version bumps that fall within the version range of the update.
5.  Report any breaking changes to the user and request confirmation before proceeding. Key areas to check for changes include:
    - `ReviewFoundation` constructor and methods.
    - `StoreReviewRequester` configuration.
    - `IReviewLocalDb` interface.
    - Public method signatures.

## 2. Update Process

### 2.1. Update `pubspec.yaml`

Modify the `pubspec.yaml` file to set the desired new version for `xsoulspace_review` and any related store-specific packages.

**Example:**

```yaml
# pubspec.yaml
dependencies:
  # Update from ^0.4.0-beta.1 to ^0.5.0
  xsoulspace_review: ^0.5.0
  # Also update any store-specific packages if needed
  xsoulspace_review_google_apple: ^0.2.0
```

### 2.2. Run `pub get`

Execute `flutter pub get` in the terminal to fetch the updated dependencies.

## 3. Post-Update Integration

### 3.1. Apply Code Modifications for Breaking Changes

If breaking changes were identified, the agent must now apply the necessary code modifications.

**Agent Action:**

- Based on the `CHANGELOG.md`, modify the existing integration code. This could involve:
  - Changing constructor parameters for `ReviewFoundation` or `StoreReviewRequester`.
  - Updating method calls that have changed.
  - Implementing new required methods in the `IReviewLocalDb` implementation if the interface has changed.

### 3.2. Resolve Analysis Issues

After applying changes, run `dart analyze` to identify any static analysis errors or warnings introduced by the update. The agent should attempt to resolve these issues automatically.

## 4. Validation

To validate the update, perform the following checks:

1.  The app compiles and runs without errors on the new version.
2.  The core functionality, specifically `reviewFoundation.requestReview(context)`, works as expected.
3.  Run any existing tests related to the review functionality to ensure they still pass.
