<!--
version: 1.0.0
repository: https://github.com/xsoulspace/xsoulspace_packages/tree/main/pkgs/xsoulspace_installation_store
license: MIT
author: Arenukvern and contributors
-->

# Agentic Executable (AE) Usage Guide for xsoulspace_installation_store

This document provides a guide for an AI agent on how to use the features of the `xsoulspace_installation_store` library within a project.

## Workflow

When working with `xsoulspace_installation_store`, follow this typical workflow:

1. **Initialize**: Create a singleton instance of `InstallationStoreUtils` (preferred) or use a dependency injection container.
2. **Detect**: Call `getInstallationSource()` to get the current installation source.
3. **Decide**: Use the source enum value or platform helpers to make decisions.
4. **Cache**: Store the result if needed, as the source doesn't change during app runtime.

## Core Components

- `InstallationStoreSource`: Enum representing detected installation sources across all platforms (Android, Apple, Windows, Linux, Web).
- `InstallationStoreUtils`: Utility class for detecting the installation source (automatically selects IO or Web implementation). **Prefer singleton usage** - the class is stateless and can be safely shared.
- `InstallationTargetStore`: Enum describing intended target distribution stores.

## Singleton Pattern (Preferred)

**Agent Action:** Always prefer using a singleton instance of `InstallationStoreUtils` rather than creating multiple instances.

**Singleton Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

/// Global singleton instance of InstallationStoreUtils
final installationStoreUtils = InstallationStoreUtils();

// Usage
final source = await installationStoreUtils.getInstallationSource();
```

**Alternative: Dependency Injection**

If using a DI container (e.g., `get_it`, `provider`), register it as a singleton:

```dart
// With get_it
GetIt.instance.registerSingleton<InstallationStoreUtils>(
  InstallationStoreUtils(),
);

// Usage
final utils = GetIt.instance<InstallationStoreUtils>();
final source = await utils.getInstallationSource();
```

## Common Tasks

### Task 1: Detecting Installation Source

The primary use case is to detect where the app was installed from.

**Agent Action:**

1. Use the singleton instance of `InstallationStoreUtils` (or get it from DI container).
2. Call `getInstallationSource()` asynchronously.
3. Use the returned `InstallationStoreSource` enum value for conditional logic.

**Example Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// Singleton instance
final installationStoreUtils = InstallationStoreUtils();

Future<void> detectSource() async {
  final source = await installationStoreUtils.getInstallationSource();

  // Use the source for feature gating, analytics, etc.
  if (source.isAndroid) {
    print('App is running on Android from: ${source.name}');
  } else if (source.isApple) {
    print('App is running on Apple platform from: ${source.name}');
  }
}
```

### Task 2: Platform-Specific Feature Gating

Conditionally enable or disable features based on installation source.

**Agent Action:**

1. Detect the installation source.
2. Use platform helpers (`isAndroid`, `isApple`, `isWindows`, `isLinux`, `isWeb`) or direct enum comparison.
3. Apply feature flags or logic accordingly.

**Example Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// Singleton instance
final installationStoreUtils = InstallationStoreUtils();

Future<bool> shouldEnableFeature() async {
  final source = await installationStoreUtils.getInstallationSource();

  // Enable feature only for Google Play installations
  return source == InstallationStoreSource.androidGooglePlay;
}

// Or use platform helpers
Future<void> configureApp() async {
  final source = await installationStoreUtils.getInstallationSource();

  if (source.isAndroid) {
    // Android-specific configuration
  } else if (source.isAppleIos) {
    // iOS-specific configuration
  } else if (source.isWeb) {
    // Web-specific configuration
  }
}
```

### Task 3: Analytics Integration

Track installation source for analytics and user segmentation.

**Agent Action:**

1. Detect installation source early in app lifecycle (e.g., `main()`).
2. Send the source to your analytics service as a user property or event.
3. Optionally track conversion differences between sources.

**Example Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// Singleton instance
final installationStoreUtils = InstallationStoreUtils();

Future<void> initializeAnalytics() async {
  final source = await installationStoreUtils.getInstallationSource();

  // Set as user property
  analytics.setUserProperty('installation_source', source.name);
  analytics.setUserProperty('is_android', source.isAndroid.toString());
  analytics.setUserProperty('is_apple', source.isApple.toString());

  // Or log as event
  analytics.logEvent('app_installed', parameters: {
    'source': source.name,
    'platform': source.isAndroid ? 'android' :
                 source.isApple ? 'apple' :
                 source.isWeb ? 'web' : 'other',
  });
}
```

### Task 4: Store-Specific UI or Behavior

Display different UI or behavior based on the specific store.

**Agent Action:**

1. Detect installation source.
2. Use switch statement or if-else for specific store handling.
3. Customize UI, links, or functionality accordingly.

**Example Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';
import 'package:flutter/material.dart';

// Singleton instance
final installationStoreUtils = InstallationStoreUtils();

class StoreSpecificWidget extends StatelessWidget {
  const StoreSpecificWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InstallationStoreSource>(
      future: installationStoreUtils.getInstallationSource(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final source = snapshot.data!;

        return switch (source) {
          InstallationStoreSource.androidGooglePlay =>
            _buildGooglePlayUI(),
          InstallationStoreSource.appleIOSAppStore =>
            _buildAppStoreUI(),
          InstallationStoreSource.webItchIo =>
            _buildItchIoUI(),
          _ => _buildGenericUI(),
        };
      },
    );
  }

  Widget _buildGooglePlayUI() => Text('Google Play specific UI');
  Widget _buildAppStoreUI() => Text('App Store specific UI');
  Widget _buildItchIoUI() => Text('Itch.io specific UI');
  Widget _buildGenericUI() => Text('Generic UI');
}
```

### Task 5: Using InstallationTargetStore for Annotations

Declare intended distribution targets for documentation or configuration.

**Agent Action:**

1. Use `InstallationTargetStore` enum to annotate intended distribution channels.
2. Can be used for build configuration or documentation purposes.

**Example Implementation:**

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

// Declare target stores for this app
const targetStores = [
  InstallationTargetStore.mobileGooglePlay,
  InstallationTargetStore.mobileAppleAppStore,
];

void configureDistribution() {
  for (final store in targetStores) {
    print('Target store: ${store.name}');
  }
}
```

## Guidelines

### When to Use Installation Source Detection

- **Feature Gating**: Enable/disable features based on store policies or capabilities.
- **Analytics**: Track distribution channels and user segmentation.
- **A/B Testing**: Different experiences for different stores.
- **Store-Specific UI**: Customize branding, links, or in-app purchases per store.

### When NOT to Use

- Don't use for platform detection (use `Platform.isAndroid` or similar instead).
- Don't rely on store detection for critical app functionality (it may be unreliable).
- Don't make security decisions based solely on installation source.

## Best Practices

### 1. Use Singleton Pattern (Preferred)

Always use a singleton instance of `InstallationStoreUtils` instead of creating multiple instances:

```dart
// Global singleton
final installationStoreUtils = InstallationStoreUtils();

// Use throughout the app
final source = await installationStoreUtils.getInstallationSource();
```

If using dependency injection, register it as a singleton in your DI container.

### 2. Cache the Installation Source

The installation source doesn't change during app runtime, so cache the result:

```dart
// Singleton instance
final installationStoreUtils = InstallationStoreUtils();

InstallationStoreSource? _cachedSource;

Future<InstallationStoreSource> getInstallationSource() async {
  _cachedSource ??= await installationStoreUtils.getInstallationSource();
  return _cachedSource!;
}
```

### 3. Handle Unknown Sources Gracefully

Always handle the `unknown` source case:

```dart
final source = await installationStoreUtils.getInstallationSource();
if (source == InstallationStoreSource.unknown) {
  // Fallback to default behavior
}
```

### 4. Use Platform Helpers

Prefer using helper getters (`isAndroid`, `isApple`, `isWeb`, etc.) over string matching:

```dart
// Good
if (source.isAndroid) { /* ... */ }

// Avoid
if (source.name.startsWith('android')) { /* ... */ }
```

## Anti-Patterns

### 1. Don't Create Multiple Instances

**Avoid creating new instances in every function or widget:**

```dart
// Bad - creating multiple instances
Future<void> function1() async {
  final utils = InstallationStoreUtils(); // ❌ New instance
  await utils.getInstallationSource();
}

Future<void> function2() async {
  final utils = InstallationStoreUtils(); // ❌ Another new instance
  await utils.getInstallationSource();
}

// Good - use singleton
final installationStoreUtils = InstallationStoreUtils(); // ✅ Single instance

Future<void> function1() async {
  await installationStoreUtils.getInstallationSource(); // ✅ Reuse
}

Future<void> function2() async {
  await installationStoreUtils.getInstallationSource(); // ✅ Reuse
}
```

### 2. Don't Call `getInstallationSource()` Repeatedly

The source doesn't change, so cache it instead of calling it multiple times, even with a singleton.

### 3. Don't Assume Specific Store Detection

On IO platforms, the library may return platform defaults rather than specific stores (e.g., `androidApk` instead of `androidGooglePlay`). Don't assume perfect store detection.

### 4. Don't Block UI on Source Detection

Use `FutureBuilder` or similar patterns to handle the async nature without blocking the UI thread.
