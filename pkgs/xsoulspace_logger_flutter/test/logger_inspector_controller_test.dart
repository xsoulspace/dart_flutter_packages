
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_logger/testing.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_flutter/xsoulspace_logger_flutter.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

void main() {
  testWidgets('controller drives logs/traces/issues updates', (
    final tester,
  ) async {
    final memorySink = InMemoryLogSink();
    final triageSink = IssueTriageSink();

    final logger = Logger(
      const LoggerConfig(flushInterval: Duration(hours: 1)),
      <LogSink>[memorySink, triageSink],
    );

    final controller = LoggerInspectorController(
      logger: logger,
      triage: triageSink,
    );

    await controller.init();

    logger.error(
      'api',
      'boom',
      trace: const TraceContext(traceId: 'trace-1', spanId: 'span-1'),
      error: StateError('bad state'),
    );

    await logger.flush();
    await tester.pump();

    expect(controller.logs, isNotEmpty);
    expect(controller.issues, isNotEmpty);

    await controller.openTrace('trace-1');
    expect(controller.traceRecords, isNotEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoggerInspectorView(controller: controller, autoInit: false),
        ),
      ),
    );

    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Traces'), findsOneWidget);
    expect(find.text('Issues'), findsOneWidget);

    controller.dispose();
    await logger.dispose();
  });
}
