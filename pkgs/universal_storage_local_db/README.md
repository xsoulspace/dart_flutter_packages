# universal_storage_local_db

`LocalDbI`-backed local storage provider for Universal Storage kernels.

## Features

- Implements `StorageProvider` + `LocalEngine`
- Uses keyspace prefixing via `LocalDbStorageConfig`
- Works with `PrefsDb` (`shared_preferences`) or any custom `LocalDbI`

## Usage

```dart
final db = PrefsDb();
final provider = LocalDbStorageProvider(localDb: db);
final service = StorageService(provider);

await service.initializeWithConfig(
  const LocalDbStorageConfig(keyspacePrefix: 'my_app'),
);
```
