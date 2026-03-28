import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_flutter/xsoulspace_logger_flutter.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

void main() {
  runApp(const LoggerExampleApp());
}

class LoggerExampleApp extends StatelessWidget {
  const LoggerExampleApp({super.key});

  @override
  Widget build(final BuildContext context) => const MaterialApp(home: LoggerInspectorDemo());
}

class LoggerInspectorDemo extends StatefulWidget {
  const LoggerInspectorDemo({super.key});

  @override
  State<LoggerInspectorDemo> createState() => _LoggerInspectorDemoState();
}

class _LoggerInspectorDemoState extends State<LoggerInspectorDemo> {
  late final IssueTriageSink _triage;
  late final Logger _logger;
  late final LoggerInspectorController _controller;

  @override
  void initState() {
    super.initState();

    _triage = IssueTriageSink();
    _logger = Logger(const LoggerConfig(), <LogSink>[_triage]);
    _controller = LoggerInspectorController(logger: _logger, triage: _triage);

    unawaited(_controller.init());
    unawaited(_seedData());
  }

  Future<void> _seedData() async {
    final trace = const TraceContext(traceId: 'trace-demo', spanId: 'root');
    _logger.info('demo', 'Inspector demo started', trace: trace);
    _logger.warning('demo', 'Slow request detected', trace: trace);
    _logger.error(
      'demo',
      'Request failed',
      error: Exception('500'),
      trace: trace,
    );
    await _logger.flush();
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_logger.dispose());
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Logger Inspector')),
      body: LoggerInspectorView(controller: _controller),
    );
}
