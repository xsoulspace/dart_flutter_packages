# universal_storage_sync_utils_flutter

Flutter implementations for `universal_storage_sync_utils`.

Status: alpha (`0.1.0-dev`).

## What This Package Provides

- Folder selection + writable path checks (`pickWritableDirectory`)
- Default app path resolution (`resolveDefaultPath`)
- macOS security-scoped bookmark helpers
- Re-exports pure Dart utilities from `universal_storage_sync_utils`

## Installation

```yaml
dependencies:
  universal_storage_sync_utils: ^0.1.0-dev.13
  universal_storage_sync_utils_flutter: ^0.1.0-dev.1
```

## Usage

```dart
import 'package:universal_storage_sync_utils_flutter/universal_storage_sync_utils_flutter.dart';

Future<void> pick() async {
  final result = await pickWritableDirectory();

  switch (result) {
    case PickSuccess(config: final config):
      print('Selected path: ${config.path.path}');
    case PickFailure(reason: final reason):
      print('Failed: $reason');
    case PickCancelled():
      print('Cancelled');
  }
}
```
