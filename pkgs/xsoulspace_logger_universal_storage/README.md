# xsoulspace_logger_universal_storage

`StorageService` sink adapter for
[`xsoulspace_logger`](https://pub.dev/packages/xsoulspace_logger).

This package writes logs to any backend supported by
`universal_storage_interface` using an append + snapshot compaction model.

## Features

- Adapter sink: `UniversalStorageSink(StorageService, namespacePath)`.
- Append file strategy (`append.ndjson`) for low-latency writes.
- Periodic compaction into snapshot file (`snapshot.json`).
- Snapshot restore hook for last-known-good records.
- Sequence continuity across restarts.

## Installation

```yaml
dependencies:
  xsoulspace_logger: ^1.0.0-beta.0
  universal_storage_interface: ">=0.1.0-dev.10 <0.2.0"
  xsoulspace_logger_universal_storage: ^1.0.0-beta.0
```

## Usage

```dart
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_universal_storage/xsoulspace_logger_universal_storage.dart';

Future<void> setupLogging(StorageService storageService) async {
  final sink = UniversalStorageSink(
    storageService,
    'observability/logger',
    config: const UniversalStorageSinkConfig(
      compactionEvery: 1024,
      snapshotMaxRecords: 10000,
    ),
  );

  final logger = Logger(const LoggerConfig(), <LogSink>[sink]);

  logger.warning('sync', 'Remote conflict resolved');
  await logger.flush();

  final restored = await sink.restoreLastKnownGoodSnapshot();
  print('Restored ${restored.length} snapshot records');

  await logger.dispose();
}
```

## Storage files

- `append.ndjson`: incremental append log.
- `snapshot.json`: compacted bounded record set with metadata.

Both file names are configurable via `UniversalStorageSinkConfig`.

## License

MIT
