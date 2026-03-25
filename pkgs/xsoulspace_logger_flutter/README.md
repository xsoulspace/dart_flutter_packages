# xsoulspace_logger_flutter

Flutter inspection UI and controller for
[`xsoulspace_logger`](https://pub.dev/packages/xsoulspace_logger).

Use this package to inspect logs, trace chains, and grouped issues in-app.

## Features

- `LoggerInspectorController` for state/query orchestration.
- `LoggerInspectorView` widget with tabs:
  - `Logs`
  - `Traces`
  - `Issues`
- Search and filter controls (text, levels, categories).
- Trace drill-down from log records.
- Optional triage integration via `IssueTriageSink`.

## Installation

```yaml
dependencies:
  xsoulspace_logger: ^1.0.0-beta.0
  xsoulspace_logger_triage: ^1.0.0-beta.0
  xsoulspace_logger_flutter: ^1.0.0-beta.0
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_flutter/xsoulspace_logger_flutter.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

class LoggerScreen extends StatefulWidget {
  const LoggerScreen({super.key});

  @override
  State<LoggerScreen> createState() => _LoggerScreenState();
}

class _LoggerScreenState extends State<LoggerScreen> {
  late final Logger _logger;
  late final IssueTriageSink _triage;
  late final LoggerInspectorController _controller;

  @override
  void initState() {
    super.initState();
    _triage = IssueTriageSink();
    _logger = Logger(const LoggerConfig(), <LogSink>[_triage]);
    _controller = LoggerInspectorController(logger: _logger, triage: _triage);
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _logger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Logger Inspector')),
      body: LoggerInspectorView(controller: _controller),
    );
  }
}
```

## Notes

- The view is intentionally lightweight and intended as a default inspector.
- For production debug builds, gate visibility behind your own feature flags.

## License

MIT
