## xsoulspace_installation_store

Utilities for detecting install sources and targeting app stores across platforms.

### Features

- Detect where your app was installed from with `InstallationStoreUtils.getInstallationSource()`.
- Rich `InstallationStoreSource` enum covering Android, Apple (iOS/macOS), Windows, Linux, Web.
- Declare intended distribution targets via `InstallationTargetStore`.

### Supported platforms

- Android, iOS, macOS, Windows, Linux, Web.

### Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_installation_store: ^0.1.0
```

### Usage

```dart
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

Future<void> main() async {
  final utils = InstallationStoreUtils();
  final source = await utils.getInstallationSource();

  if (source.isAndroid) {
    // e.g. Google Play, RuStore, etc.
  } else if (source.isApple) {
    // iOS/macOS App Store/TestFlight/DMG/etc.
  } else if (source.isWeb) {
    // Self-hosted vs Itch.io
  }
}
```

`InstallationTargetStore` can be used to annotate or configure your distribution targets:

```dart
const target = InstallationTargetStore.mobileGooglePlay;
print(target.name); // "Google Play"
```

### Notes

- IO implementation returns best-effort platform defaults by `dart:io`.
- Web implementation resolves by hostname and can be extended.

### License

MIT


