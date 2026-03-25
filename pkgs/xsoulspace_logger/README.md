# xsoulspace_logger

Pure Dart observability logger core for Flutter and Dart apps.

`xsoulspace_logger` is the runtime-independent foundation package in the
`xsoulspace_logger*` stack:

- `xsoulspace_logger`: core pipeline, redaction, trace context, query APIs.
- `xsoulspace_logger_io`: durable local file sink (`dart:io`).
- `xsoulspace_logger_universal_storage`: `StorageService` sink adapter.
- `xsoulspace_logger_triage`: issue grouping/dedup/priority scoring.
- `xsoulspace_logger_flutter`: inspector controller and Flutter UI.

## Features

- Pure Dart core (`no dart:io` dependency).
- Deterministic single-writer async pipeline with sequence ordering.
- Backpressure strategy with low-priority drops first and synthetic warning.
- Privacy-first redaction with depth/size guards.
- Trace-aware records (`TraceContext`) and scoped child loggers.
- Programmatic inspection APIs: `query`, `watch`, `trace`.
- Lazy logging methods (`traceLazy`, `debugLazy`) to avoid expensive builds.

## Installation

```yaml
dependencies:
  xsoulspace_logger: ^1.0.0-beta.0
```

## Quick start

```dart
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

final class PrintSink implements LogSink {
  @override
  Future<void> init() async {}

  @override
  void enqueue(LogRecord record) {
    print('[${record.level.name}] ${record.category}: ${record.message}');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> main() async {
  final logger = Logger(
    const LoggerConfig(minLevel: LogLevel.debug),
    <LogSink>[PrintSink()],
  );

  await logger.init();

  final traced = logger.child(
    category: 'auth',
    fields: <String, Object?>{'appVersion': '1.2.3'},
    trace: const TraceContext(traceId: 'trace-1', spanId: 'span-1'),
  );

  traced.info('auth', 'User sign-in started');
  traced.debugLazy('auth', () => 'Heavy debug: ${DateTime.now()}');
  traced.error('auth', 'Sign-in failed', error: StateError('invalid token'));

  final recentErrors = await logger.query(
    const LogQuery(levels: <LogLevel>{LogLevel.error, LogLevel.critical}),
  );

  print('Errors: ${recentErrors.length}');

  await logger.flush();
  await logger.dispose();
}
```

## Configuration defaults

- `flushInterval`: `1 second`
- `flushBatchSize`: `256`
- `queueCapacity`: `20000`
- `hardQueueCapacity`: `queueCapacity + 1000`
- `disposeTimeout`: `5 seconds`
- `backpressureWarningInterval`: `30 seconds`

## Redaction defaults

Sensitive keys are redacted by default:

- `password`
- `token`
- `secret`
- `authorization`
- `cookie`
- `session`
- `apiKey`
- `email`
- `phone`

And the sanitizer enforces:

- max depth: `6`
- max serialized value: `4 KB`
- max persisted stack trace lines: `120`

## Migration from pre-1.0 logger

This release is a breaking redesign.

- Old singleton/reset API (`Logger.reset`) was removed.
- Old file writer in core was removed.
- `LogLevel.verbose` became `LogLevel.trace`.
- File persistence moved to `xsoulspace_logger_io`.
- You now compose sinks explicitly in `Logger(config, sinks)`.

## Related packages

- [xsoulspace_logger_io](https://pub.dev/packages/xsoulspace_logger_io)
- [xsoulspace_logger_universal_storage](https://pub.dev/packages/xsoulspace_logger_universal_storage)
- [xsoulspace_logger_triage](https://pub.dev/packages/xsoulspace_logger_triage)
- [xsoulspace_logger_flutter](https://pub.dev/packages/xsoulspace_logger_flutter)

## License

MIT
