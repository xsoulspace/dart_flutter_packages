# xsoulspace_logger_io

Durable local-file sink (`dart:io`) for
[`xsoulspace_logger`](https://pub.dev/packages/xsoulspace_logger).

This package persists records as NDJSON segments with crash recovery and
retention controls.

## Features

- NDJSON segment storage format.
- Monotonic persisted sequence numbers.
- Segment rotation by max file size.
- Retention by max age and total bytes.
- Recovery protocol for truncated/corrupted trailing lines.
- Periodic durability flush and urgent flush for warning/error bursts.

## Installation

```yaml
dependencies:
  xsoulspace_logger: ^1.0.0-beta.0
  xsoulspace_logger_io: ^1.0.0-beta.0
```

## Usage

```dart
import 'dart:io';

import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_io/xsoulspace_logger_io.dart';

Future<void> main() async {
  final sink = IoLogSink(
    IoLogSinkConfig(
      directoryPath: Directory.systemTemp.path,
      segmentMaxBytes: 8 * 1024 * 1024,
      retentionMaxAge: const Duration(days: 7),
      retentionMaxBytes: 50 * 1024 * 1024,
      fsyncInterval: const Duration(seconds: 5),
    ),
  );

  final logger = Logger(
    const LoggerConfig(minLevel: LogLevel.info),
    <LogSink>[sink],
  );

  logger.info('app', 'Application started');
  logger.error('api', 'Request failed', error: Exception('timeout'));

  await logger.flush();
  await logger.dispose();
}
```

## Persistence model

- File format: one JSON log record per line (NDJSON).
- Default segment size: `8 MB`.
- Default retention: `7 days` and `50 MB total`.
- Recovery: on startup, invalid trailing JSON is truncated to the last valid line.

## Notes

- This package is VM/desktop/server oriented because it depends on `dart:io`.
- For runtime-agnostic logging, keep core in `xsoulspace_logger` and choose
  adapters conditionally.

## License

MIT
