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
