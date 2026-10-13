# universal_storage_filesystem

Filesystem provider for Universal Storage.

Status: alpha (`0.1.0-dev`).

## Installation

```yaml
dependencies:
  universal_storage_filesystem: ^0.1.0-dev.12
  universal_storage_interface: ^0.1.0-dev.10
```

## Usage

```dart
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

Future<void> main() async {
  final service = StorageService(FileSystemStorageProvider());
  await service.initializeWithConfig(
    FileSystemConfig(
      filePathConfig: FilePathConfig({'path': '/path/to/data'}),
    ),
  );

  await service.saveFile('hello.txt', 'Hello');
  final content = await service.readFile('hello.txt');
  print(content);
}
```

## Notes

- Not supported on web.
- Creates parent directories automatically.
- Includes durability/recovery internals under `.us/` in the workspace root.

## Permission-aware file state

The optional `StorageFileStatePort` supports permission-aware text recovery on
the native POSIX route. It records explicit 0644 creation intent, preserves
existing modes on updates, and restores content plus mode through the same
durability writer. Staging is exclusive and starts at 0600 before private bytes
are written. Mode verification precedes atomic publication; prepared replay
checks both checksum and mode without chmodding an unexplained target.
Symlinks, nonregular files, special mode bits and owner-unreadable states refuse.

The native-only `onWriteBoundary` observer is a trusted diagnostic/test port;
it supplies no tool, policy or transaction authority. macOS arm64 process-kill
controls cover private staging, prepared publication and published-before-commit
boundaries. Other-platform execution and power-loss qualification are separate.
See [ADR 0068](../../docs/decisions/0068_file_state_live_apply_recovery.md).

## Optional Path Access Override

You can inject custom platform path access logic.

With your own implementation:

```dart
final provider = FileSystemStorageProvider(
  pathAccess: CallbackFileSystemPathAccess(
    resolveDirectory: (config) async => Directory(config.path.path),
    releaseDirectory: (config) async {},
  ),
);
```

Or, if you depend on `universal_storage_sync_utils_flutter`, you can wire its Flutter
helpers explicitly:

```dart
import 'package:universal_storage_sync_utils_flutter/universal_storage_sync_utils_flutter.dart';

final provider = FileSystemStorageProvider(
  pathAccess: CallbackFileSystemPathAccess(
    resolveDirectory: resolvePlatformDirectoryOfConfig,
    releaseDirectory: disposePathOfFileConfig,
  ),
);
```
