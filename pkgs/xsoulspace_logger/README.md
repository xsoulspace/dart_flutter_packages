# xsoulspace_logger

Generic configurable logger for Dart applications with console and file output support.

## Features

- **Multiple log levels**: VERBOSE, DEBUG, INFO, WARNING, ERROR
- **Configurable outputs**: Console and/or file (individually toggleable)
- **Async file writes**: Non-blocking with automatic buffering
- **Log rotation**: Time and size-based rotation with cleanup
- **Structured logging**: Optional data maps for context
- **Presets**: Debug, production, verbose configurations

## Usage

### Basic Setup

```dart
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

Future<void> main() async {
  // Initialize logger with debug preset
  final logger = Logger(LoggerConfig.debug());
  await logger.init();

  logger.info('APP', 'Application started');
  logger.debug('AUTH', 'User logged in', data: {'userId': '123'});
  logger.warning('API', 'Rate limit approaching');
  logger.error('DB', 'Connection failed', error: exception, stackTrace: stack);
}
```

### Configuration Presets

```dart
// Debug mode: VERBOSE level, console + file
final logger = Logger(LoggerConfig.debug());
await logger.init();

// Production: INFO level, file only
final logger = Logger(LoggerConfig.production());
await logger.init();

// Verbose: All logs, console + file, large files
final logger = Logger(LoggerConfig.verbose());
await logger.init();

// Silent: Errors only
final logger = Logger(LoggerConfig.silent());
await logger.init();

// Console only (no files)
final logger = Logger(LoggerConfig.consoleOnly());
await logger.init();
```

### Custom Configuration

```dart
final config = LoggerConfig(
  minLevel: LogLevel.debug,
  enableConsole: true,
  enableFile: true,
  logDirectory: '/var/logs/myapp',
  enableRotation: true,
  maxFileSizeMB: 20,
  maxFileCount: 10,
);

final logger = Logger(config);
await logger.init();
```

### Log Methods

```dart
logger.verbose('CATEGORY', 'Detailed diagnostic info');
logger.debug('CATEGORY', 'Debug information');
logger.info('CATEGORY', 'Normal operation');
logger.warning('CATEGORY', 'Potential problem');
logger.error('CATEGORY', 'Serious error', error: e, stackTrace: stack);

// With structured data
logger.info('API', 'Request completed', data: {
  'endpoint': '/users',
  'duration': 123,
  'status': 200,
});
```

### Output Examples

**Console** (colored, concise):

```
[12:34:56] 🟢 INFO    [API] Request completed | endpoint=/users, duration=123, status=200
[12:34:57] 🔴 ERROR   [DB] Connection failed
```

**File** (structured, detailed):

```
[2025-10-11T12:34:56.789] [INFO] [API] Request completed
  endpoint: /users
  duration: 123
  status: 200

[2025-10-11T12:34:57.123] [ERROR] [DB] Connection failed
  error: SocketException: Connection refused
  stackTrace:
    #0      Socket.connect (dart:io)
    #1      DatabaseClient.connect (package:myapp/db.dart:45)
```

### Initialization and Cleanup

```dart
// Initialize logger after creation
final logger = Logger(LoggerConfig.debug());
await logger.init();

// Flush remaining buffer before exit
await logger.dispose();
```

## License

MIT
