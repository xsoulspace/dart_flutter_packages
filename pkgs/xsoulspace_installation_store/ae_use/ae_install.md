<!--
version: 1.0.0
repository: https://github.com/xsoulspace/xsoulspace_packages/tree/main/pkgs/xsoulspace_installation_store
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Installation Guide for xsoulspace_installation_store

This document provides instructions for an AI agent to install, configure, and integrate the `xsoulspace_installation_store` library.

## 1. Installation

### 1.1. Add Dependencies

Add `xsoulspace_installation_store` to `pubspec.yaml`.

```yaml
dependencies:
  xsoulspace_installation_store: ^0.1.2
```

### 1.2. Run `pub get`

Execute `flutter pub get` in the terminal to fetch the dependencies.

## 2. Configuration

No additional configuration is required. The library automatically selects the appropriate implementation (IO or Web) based on the platform using conditional exports.

## 3. Integration

### 3.1. Import the Library

Import the main library file in your Dart code:

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';
```

### 3.2. Initialize InstallationStoreUtils

**Prefer using a singleton instance** of `InstallationStoreUtils`. The class is stateless and can be safely shared across the application.

**Agent Action:**

1. Create a global singleton instance of `InstallationStoreUtils` (preferred) or register it as a singleton in your dependency injection container.
2. Determine where installation source detection is needed (e.g., app startup, analytics initialization, feature gating).
3. Use the singleton instance to call `getInstallationSource()` to detect the source.

**Example Integration in `main.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// Global singleton instance
final installationStoreUtils = InstallationStoreUtils();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect installation source on app start using singleton
  final source = await installationStoreUtils.getInstallationSource();

  // Store or use the source as needed (e.g., for analytics, feature flags)
  debugPrint('App installed from: ${source.name}');

  runApp(const MyApp());
}
```

**Alternative: Dependency Injection**

If using a DI container, register it as a singleton:

```dart
// With get_it
GetIt.instance.registerSingleton<InstallationStoreUtils>(
  InstallationStoreUtils(),
);

// Usage
final utils = GetIt.instance<InstallationStoreUtils>();
final source = await utils.getInstallationSource();
```

### 3.3. Platform-Specific Considerations

The library uses conditional exports to provide platform-appropriate implementations:
- **IO platforms** (Android, iOS, macOS, Windows, Linux): Uses `InstallationStoreUtils` from `installation_store_utils_io.dart`
- **Web platform**: Uses `InstallationStoreUtils` from `installation_store_utils_web.dart`

No additional platform-specific setup is required.

## 4. Usage Examples

All examples use the singleton pattern. Ensure you have a global instance defined as shown in section 3.2.

### 4.1. Feature Gating Based on Installation Source

```dart
// Using the singleton instance (defined elsewhere)
final source = await installationStoreUtils.getInstallationSource();

if (source.isAndroid && source == InstallationStoreSource.androidGooglePlay) {
  // Enable Google Play-specific features
} else if (source == InstallationStoreSource.webItchIo) {
  // Enable Itch.io-specific features
}
```

### 4.2. Analytics Integration

```dart
// Using the singleton instance (defined elsewhere)
final source = await installationStoreUtils.getInstallationSource();

// Send installation source to analytics
analytics.setUserProperty('installation_source', source.name);
```

### 4.3. Store-Specific Behavior

```dart
// Using the singleton instance (defined elsewhere)
final source = await installationStoreUtils.getInstallationSource();

switch (source) {
  case InstallationStoreSource.androidGooglePlay:
    // Google Play logic
    break;
  case InstallationStoreSource.appleIOSAppStore:
    // App Store logic
    break;
  case InstallationStoreSource.webSelfhost:
    // Self-hosted web logic
    break;
  default:
    // Default logic
}
```

## 5. Validation

To validate the installation, perform the following checks:

1. The app compiles and runs without errors on the target platform.
2. A call to `await installationStoreUtils.getInstallationSource()` (using the singleton) returns a valid `InstallationStoreSource` enum value.
3. On web, the source correctly identifies `webItchIo` when hosted on itch.io, or `webSelfhost` otherwise.
4. On IO platforms, the source returns platform-appropriate defaults (may require native platform detection implementation for specific stores).
5. The singleton instance is reused throughout the application rather than creating multiple instances.

## 6. Known Limitations

- IO implementation currently returns best-effort platform defaults based on `dart:io`. Specific store detection (e.g., Google Play vs. APK) may require additional native platform code.
- Web implementation resolves source by hostname and can be extended for additional hosts.

