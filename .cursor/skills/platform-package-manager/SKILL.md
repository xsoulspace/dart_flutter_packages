---
name: platform-package-manager
description: Manage platform-specific package implementations for iOS, Android, Web, Desktop, and various app stores. Use when working with platform-specific code, conditional imports, or when user mentions platforms, stores, or cross-platform support.
---

# Platform-Specific Package Manager

Handle platform-specific implementations across multiple platforms and app stores.

## Quick Start

When working with platform-specific packages:

1. Identify target platforms
2. Structure platform-specific code
3. Use conditional imports
4. Validate platform implementations

## Platform Categories

### Mobile Platforms
- **Android** - Google Play, Huawei AppGallery, RuStore, Samsung Galaxy Store
- **iOS** - Apple App Store

### Desktop Platforms
- **macOS** - Mac App Store
- **Windows** - Microsoft Store
- **Linux** - Snap Store

### Web Platform
- **Web** - Browser-based applications

## Package Families by Platform

### Review Packages (Store-Specific)

```
xsoulspace_review_interface (core)
├── xsoulspace_review_google_apple (iOS/Android - App Store/Google Play)
├── xsoulspace_review_huawei (Android - Huawei AppGallery)
├── xsoulspace_review_rustore (Android - RuStore)
├── xsoulspace_review_snapstore (Linux - Snap Store)
└── xsoulspace_review_web (Web)
```

### Monetization Packages (Store-Specific)

```
xsoulspace_monetization_interface (core)
├── xsoulspace_monetization_google_apple (iOS/Android)
├── xsoulspace_monetization_huawei (Android - Huawei)
└── xsoulspace_monetization_rustore (Android - RuStore)
```

### Ads Packages (Platform-Specific)

```
xsoulspace_monetization_ads_interface (core)
├── xsoulspace_monetization_ads_foundation
└── xsoulspace_monetization_ads_yandex (Android/iOS)
```

## Platform-Specific Code Structure

### Pattern 1: Conditional Imports

Main export file with platform selection:

```dart
// lib/package_name.dart
library;

export 'src/package_name_stub.dart'
    if (dart.library.io) 'src/package_name_io.dart'
    if (dart.library.html) 'src/package_name_web.dart';
```

**File structure:**
```
lib/
├── src/
│   ├── package_name_stub.dart    # Fallback/error implementation
│   ├── package_name_io.dart      # Mobile/Desktop implementation
│   └── package_name_web.dart     # Web implementation
└── package_name.dart              # Main export with conditionals
```

### Pattern 2: Platform Detection

```dart
// lib/src/package_name_stub.dart
class PlatformImplementation {
  const PlatformImplementation();
  
  void unsupportedError() {
    throw UnsupportedError(
      'This platform is not supported. '
      'Supported platforms: iOS, Android, Web',
    );
  }
}
```

```dart
// lib/src/package_name_io.dart
import 'dart:io' show Platform;

class PlatformImplementation {
  const PlatformImplementation();
  
  String getPlatform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
```

```dart
// lib/src/package_name_web.dart
class PlatformImplementation {
  const PlatformImplementation();
  
  String getPlatform() => 'Web';
}
```

### Pattern 3: Store-Specific Implementation

```dart
/// {@template store_reviewer}
/// Platform-specific app review functionality.
///
/// Implementations:
/// * [GoogleAppleReviewer] - iOS App Store and Google Play
/// * [HuaweiReviewer] - Huawei AppGallery
/// * [RuStoreReviewer] - RuStore
/// * [SnapStoreReviewer] - Linux Snap Store
/// * [WebReviewer] - Web browsers
/// {@endtemplate}
abstract class StoreReviewer {
  /// {@macro store_reviewer}
  const StoreReviewer();
  
  /// Request app review from the user.
  Future<void> requestReview();
  
  /// Check if review is available on this platform.
  Future<bool> isAvailable();
}
```

## Creating Platform-Specific Packages

### Step 1: Create Interface Package

```bash
cd pkgs
mkdir <family>_interface
cd <family>_interface
```

Create core interface:

```dart
// lib/<family>_interface.dart
library;

export 'src/<family>_interface.dart';
```

```dart
// lib/src/<family>_interface.dart
/// {@template family_interface}
/// Core interface for <family> functionality.
/// {@endtemplate}
abstract class FamilyInterface {
  /// {@macro family_interface}
  const FamilyInterface();
  
  /// Platform-specific method.
  Future<void> method();
}
```

### Step 2: Create Platform Implementation

```bash
cd pkgs
mkdir <family>_<platform>
cd <family>_<platform>
```

Add dependency on interface:

```yaml
# pubspec.yaml
dependencies:
  <family>_interface:
    path: ../<family>_interface
```

Implement interface:

```dart
// lib/<family>_<platform>.dart
library;

export 'src/<platform>_implementation.dart';
```

```dart
// lib/src/<platform>_implementation.dart
import 'package:<family>_interface/<family>_interface.dart';

/// {@template platform_implementation}
/// <Platform> implementation of [FamilyInterface].
/// {@endtemplate}
class PlatformImplementation implements FamilyInterface {
  /// {@macro platform_implementation}
  const PlatformImplementation();
  
  @override
  Future<void> method() async {
    // Platform-specific implementation
  }
}
```

### Step 3: Platform-Specific Configuration

**For Android (build.gradle):**

```dart
// lib/src/android_config.dart
/// Android-specific configuration
class AndroidConfig {
  static const String minSdkVersion = '21';
  static const String targetSdkVersion = '34';
}
```

**For iOS (Info.plist):**

```dart
// lib/src/ios_config.dart
/// iOS-specific configuration
class IosConfig {
  static const String minimumOSVersion = '12.0';
}
```

**For Web:**

```dart
// lib/src/web_config.dart
/// Web-specific configuration
class WebConfig {
  static const List<String> supportedBrowsers = [
    'Chrome',
    'Firefox',
    'Safari',
    'Edge',
  ];
}
```

## Platform Detection Utilities

### Runtime Platform Detection

```dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

enum AppPlatform {
  android,
  ios,
  web,
  macos,
  windows,
  linux,
  unknown,
}

class PlatformDetector {
  static AppPlatform get current {
    if (kIsWeb) return AppPlatform.web;
    
    if (Platform.isAndroid) return AppPlatform.android;
    if (Platform.isIOS) return AppPlatform.ios;
    if (Platform.isMacOS) return AppPlatform.macos;
    if (Platform.isWindows) return AppPlatform.windows;
    if (Platform.isLinux) return AppPlatform.linux;
    
    return AppPlatform.unknown;
  }
  
  static bool get isAndroid => current == AppPlatform.android;
  static bool get isIOS => current == AppPlatform.ios;
  static bool get isWeb => current == AppPlatform.web;
  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => current == AppPlatform.macos || 
                                current == AppPlatform.windows || 
                                current == AppPlatform.linux;
}
```

### Store Detection

```dart
enum AppStore {
  googlePlay,
  appleAppStore,
  huaweiAppGallery,
  ruStore,
  samsungGalaxyStore,
  snapStore,
  microsoftStore,
  macAppStore,
  web,
  unknown,
}

class StoreDetector {
  /// Detect which store the app was installed from.
  /// 
  /// This typically requires platform-specific code
  /// and may use package: store_checker
  static Future<AppStore> detectStore() async {
    // Implementation would check:
    // - Installer package name (Android)
    // - Receipt validation (iOS)
    // - Environment variables (Desktop)
    // - URL parameters (Web)
    
    return AppStore.unknown;
  }
}
```

## Platform Compatibility Matrix

### Generate Compatibility Matrix

```dart
/// Platform support matrix for package
class PlatformSupport {
  static const Map<String, bool> support = {
    'Android': true,
    'iOS': true,
    'Web': false,
    'macOS': false,
    'Windows': false,
    'Linux': false,
  };
  
  static bool isSupported(String platform) {
    return support[platform] ?? false;
  }
  
  static List<String> get supportedPlatforms {
    return support.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
  }
}
```

### Document Platform Support

In README.md:

```markdown
## Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| Android  | ✅ | API 21+ |
| iOS      | ✅ | iOS 12+ |
| Web      | ❌ | Not supported |
| macOS    | ✅ | macOS 10.14+ |
| Windows  | ✅ | Windows 10+ |
| Linux    | ✅ | Via Snap Store |

### Store Support

| Store | Platform | Supported |
|-------|----------|-----------|
| Google Play | Android | ✅ |
| Apple App Store | iOS | ✅ |
| Huawei AppGallery | Android | ✅ |
| RuStore | Android | ✅ |
| Snap Store | Linux | ✅ |
```

## Testing Platform-Specific Code

### Test Structure

```
test/
├── unit/
│   ├── android_test.dart
│   ├── ios_test.dart
│   └── web_test.dart
├── integration/
│   └── platform_integration_test.dart
└── platform_test.dart
```

### Mock Platform Behavior

```dart
import 'package:test/test.dart';

void main() {
  group('Platform-specific behavior', () {
    test('Android implementation', () {
      // Test Android-specific code
    });
    
    test('iOS implementation', () {
      // Test iOS-specific code
    });
    
    test('Web implementation', () {
      // Test Web-specific code
    });
  });
}
```

## Platform-Specific Dependencies

### Conditional Dependencies

```yaml
# pubspec.yaml
dependencies:
  # Common dependencies
  meta: ^1.16.0
  
  # Platform-specific dependencies
  # (These are automatically excluded on unsupported platforms)

dev_dependencies:
  test: ^1.25.0
```

### Plugin Dependencies

For packages requiring native code:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Android-specific
  # (Add via plugin)
  
  # iOS-specific
  # (Add via plugin)
```

## Validation Checklist

When creating platform-specific packages:

```
Package: <name>
Target Platforms: [list]

Structure:
- [ ] Interface package created
- [ ] Platform implementations created
- [ ] Conditional imports configured
- [ ] Stub implementation for unsupported platforms

Implementation:
- [ ] Platform detection works
- [ ] Store detection works (if needed)
- [ ] Platform-specific code isolated
- [ ] Fallback behavior defined

Testing:
- [ ] Unit tests for each platform
- [ ] Integration tests
- [ ] Manual testing on target platforms

Documentation:
- [ ] Platform support documented
- [ ] Store support documented
- [ ] Platform-specific setup documented
- [ ] Examples for each platform
```

## Common Patterns

### Pattern: Factory Constructor

```dart
abstract class PlatformService {
  factory PlatformService() {
    if (kIsWeb) return WebService();
    if (Platform.isAndroid) return AndroidService();
    if (Platform.isIOS) return IosService();
    throw UnsupportedError('Platform not supported');
  }
  
  Future<void> execute();
}
```

### Pattern: Platform Channel

For Flutter plugins:

```dart
import 'package:flutter/services.dart';

class PlatformChannel {
  static const MethodChannel _channel = 
      MethodChannel('com.example.package/channel');
  
  static Future<String> getPlatformVersion() async {
    final version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
```

### Pattern: Feature Flags

```dart
class PlatformFeatures {
  static bool get supportsInAppReview {
    return Platform.isAndroid || Platform.isIOS;
  }
  
  static bool get supportsInAppPurchase {
    return Platform.isAndroid || 
           Platform.isIOS || 
           Platform.isMacOS;
  }
  
  static bool get supportsNotifications {
    return !kIsWeb;
  }
}
```

## Quick Reference

```bash
# Create platform-specific package structure
mkdir -p lib/src
touch lib/src/package_stub.dart
touch lib/src/package_io.dart
touch lib/src/package_web.dart

# Test on specific platform
flutter test --platform chrome  # Web
flutter test -d <device-id>     # Specific device

# Check platform support
grep -r "Platform.is" lib/

# List platform-specific packages
ls pkgs/*_google_apple pkgs/*_huawei pkgs/*_rustore pkgs/*_web
```

## Store-Specific Resources

### Google Play (Android)
- Package: `xsoulspace_review_google_apple`
- API: Google Play In-App Review API
- Requires: Google Play Services

### Apple App Store (iOS)
- Package: `xsoulspace_review_google_apple`
- API: StoreKit SKStoreReviewController
- Requires: iOS 10.3+

### Huawei AppGallery (Android)
- Package: `xsoulspace_review_huawei`
- API: Huawei HMS Core
- Requires: Huawei Mobile Services

### RuStore (Android)
- Package: `xsoulspace_review_rustore`
- API: RuStore SDK
- Requires: RuStore app installed

### Snap Store (Linux)
- Package: `xsoulspace_review_snapstore`
- API: Snapcraft ratings
- Requires: Snap environment
