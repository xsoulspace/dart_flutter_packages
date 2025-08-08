# universal_storage_filesystem

Filesystem provider implementing `StorageProvider` using the local filesystem.

## Install

```yaml
dependencies:
  universal_storage_interface: ^0.1.0-dev.2
  universal_storage_filesystem: ^0.1.0-dev.2
```

## Usage

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';

final service = StorageService(FileSystemStorageProvider());
await service.initializeWithConfig(
  FileSystemConfig(basePath: '/path/to/data'),
);

await service.saveFile('hello.txt', 'Hello');
final content = await service.readFile('hello.txt');
```

## Notes

- Not supported on web
- Creates parent directories automatically

## License

MIT
