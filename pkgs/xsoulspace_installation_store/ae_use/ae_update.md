<!--
version: 1.0.0
repository: https://github.com/xsoulspace/xsoulspace_packages/tree/main/pkgs/xsoulspace_installation_store
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Update Guide for xsoulspace_installation_store

This document provides instructions for an AI agent to update the `xsoulspace_installation_store` library to a new version.

## 1. Pre-Update Analysis

### 1.1. Check for Breaking Changes

Before performing the update, the agent must check the `CHANGELOG.md` of `xsoulspace_installation_store` for breaking changes between the current and target versions.

**Agent Action:**

1. Identify the current version of `xsoulspace_installation_store` in the user's `pubspec.yaml`.
2. Determine the latest available version to update to.
3. Fetch and parse the `CHANGELOG.md` from the library's repository.
4. Identify any entries marked as "BREAKING" or major version bumps that fall within the version range of the update.
5. Report any breaking changes to the user and request confirmation before proceeding. Key areas to check for changes include:
   - `InstallationStoreUtils` constructor and method signatures.
   - `InstallationStoreSource` enum values (additions, removals, renames).
   - `InstallationTargetStore` enum values (additions, removals, renames).
   - Changes to conditional exports or platform-specific implementations.

## 2. Update Process

### 2.1. Update `pubspec.yaml`

Modify the `pubspec.yaml` file to set the desired new version for `xsoulspace_installation_store`.

**Example:**

```yaml
# pubspec.yaml
dependencies:
  # Update from ^0.1.2 to ^0.2.0
  xsoulspace_installation_store: ^0.2.0
```

### 2.2. Run `pub get`

Execute `flutter pub get` in the terminal to fetch the updated dependencies.

## 3. Post-Update Integration

### 3.1. Apply Code Modifications for Breaking Changes

If breaking changes were identified, the agent must now apply the necessary code modifications.

**Agent Action:**

- Based on the `CHANGELOG.md`, modify the existing integration code. This could involve:
  - Updating enum value references if `InstallationStoreSource` or `InstallationTargetStore` values were renamed or removed.
  - Adjusting switch statements to handle new enum cases or remove deprecated ones.
  - Updating method calls if `InstallationStoreUtils` API changed.

**Example Scenario - New Enum Values:**

If the update adds new `InstallationStoreSource` values:

```dart
// Before update
switch (source) {
  case InstallationStoreSource.androidGooglePlay:
    // Handle Google Play
    break;
  default:
    // Handle others
}

// After update - add new cases
switch (source) {
  case InstallationStoreSource.androidGooglePlay:
    // Handle Google Play
    break;
  case InstallationStoreSource.androidRuStore: // New value
    // Handle RuStore
    break;
  default:
    // Handle others
}
```

### 3.2. Resolve Analysis Issues

After applying changes, run `dart analyze` to identify any static analysis errors or warnings introduced by the update. The agent should attempt to resolve these issues automatically.

## 4. Validation

To validate the update, perform the following checks:

1. The app compiles and runs without errors on the new version.
2. The core functionality, specifically `await InstallationStoreUtils().getInstallationSource()`, works as expected and returns valid enum values.
3. Any platform-specific behavior (web vs. IO) continues to work correctly.
4. Run any existing tests related to installation source detection to ensure they still pass.
