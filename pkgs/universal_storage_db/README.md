# Universal Storage DB

Typed local DB wrapper on top of Universal Storage.

Status: early alpha (`0.1.0-dev`). Not production-ready.

## What It Provides

- `UniversalStorageDb`: bootstraps `StorageService` from `StorageConfig`
- `LocalDbUniversalStorageImpl`: key/value style typed API
  - `setBool` / `getBool`
  - `setInt` / `getInt`
  - `setString` / `getString`
  - `setMap` / `getMap`
  - list/object helpers
- Configurable file routing and file format via `UniversalStorageDbConfig`

## Installation

```yaml
dependencies:
  universal_storage_db: ^0.1.0-dev.5
  universal_storage_sync: ^0.1.0-dev.10
```

## Quick Start

```dart
import 'package:universal_storage_db/universal_storage_db.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

Future<void> main() async {
  final dbCore = UniversalStorageDb(
    storageConfig: FileSystemConfig(
      filePathConfig: FilePathConfig({'path': '/path/to/storage'}),
    ),
    config: const UniversalStorageDbConfig(),
  );
  await dbCore.init();

  final db = LocalDbUniversalStorageImpl(db: dbCore);
  await db.init();

  await db.setBool(key: 'dark_mode', value: true);
  final darkMode = await db.getBool(key: 'dark_mode');
  print(darkMode);

  await db.setString(key: 'username', value: 'john');
  final username = await db.getString(key: 'username');
  print(username);
}
```

## Current Limitations (2026-03-02)

- Coverage is limited; dedicated package tests are currently missing.
- API and internal file layout are still evolving.
- `UniversalStorageDb.pickPathForConfig()` is a placeholder and not implemented.

## Production Path

For full production-completeness requirements and sequencing:

- `../universal_storage_docs/PRODUCTION_COMPLETENESS_PATH.md`
