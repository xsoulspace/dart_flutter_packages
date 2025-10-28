<!--
version: 1.0.0
repository: https://github.com/xsoulspace/xsoulspace_packages/tree/main/pkgs/xsoulspace_installation_store
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Uninstallation Guide for xsoulspace_installation_store

This document provides instructions for an AI agent to completely and safely uninstall the `xsoulspace_installation_store` library from a project.

## 1. Code Removal

### 1.1. Remove `InstallationStoreUtils` Usage

Search the codebase for all usages of `InstallationStoreUtils` and remove them.

**Agent Action:**

1. Search for all imports of `package:xsoulspace_installation_store/xsoulspace_installation_store.dart`.
2. Find all instantiations of `InstallationStoreUtils`.
3. Find all calls to `getInstallationSource()`.
4. Remove the code blocks that use these APIs.

**Example Code to Remove:**

```dart
// DELETE THIS BLOCK
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// ... inside code ...

// DELETE THIS BLOCK
final utils = InstallationStoreUtils();
final source = await utils.getInstallationSource();
```

### 1.2. Remove `InstallationStoreSource` Usage

Search for all usages of `InstallationStoreSource` enum and remove associated logic.

**Agent Action:**

1. Search for references to `InstallationStoreSource` enum values.
2. Remove switch statements, if-else blocks, or any conditional logic based on installation source.
3. Replace with appropriate fallback logic if needed.

**Example Code to Remove:**

```dart
// DELETE THIS BLOCK
switch (source) {
  case InstallationStoreSource.androidGooglePlay:
    // Store-specific logic
    break;
  // ... other cases
}
```

### 1.3. Remove `InstallationTargetStore` Usage (if used)

If `InstallationTargetStore` was used anywhere, remove those references as well.

**Agent Action:**

1. Search for references to `InstallationTargetStore`.
2. Remove any code that declares or uses target store configurations.

### 1.4. Clean Up Imports

Remove all unused imports related to `xsoulspace_installation_store` from the modified files.

## 2. Dependency Removal

### 2.1. Update `pubspec.yaml`

Remove `xsoulspace_installation_store` from the `dependencies` section of your `pubspec.yaml` file.

**Before:**

```yaml
dependencies:
  xsoulspace_installation_store: ^0.1.2
```

**After:**

```yaml
dependencies:
  # xsoulspace_installation_store removed
```

### 2.2. Run `pub get`

Execute `flutter pub get` in the terminal to remove the dependency from your project.

## 3. Validation

To validate the uninstallation, perform the following checks:

1. The app compiles and runs without any errors.
2. A global search for `xsoulspace_installation_store`, `InstallationStoreUtils`, `InstallationStoreSource`, and `InstallationTargetStore` should yield no results in the codebase (apart from `pubspec.lock`).
3. Verify that any feature-gating or analytics code that depended on installation source detection has been updated or removed appropriately.
