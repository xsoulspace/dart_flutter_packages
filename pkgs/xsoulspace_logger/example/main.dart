import 'package:xsoulspace_logger/xsoulspace_logger.dart';

final class StdoutSink implements LogSink {
  @override
  Future<void> init() async {}

  @override
  void enqueue(final LogRecord record) {
    print('[${record.level.name}] ${record.category}: ${record.message}');
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> main() async {
  final logger = Logger(const LoggerConfig(minLevel: LogLevel.debug), <LogSink>[
    StdoutSink(),
  ]);

  logger.info('example', 'Logger initialized');
  logger.debugLazy(
    'example',
    () => 'Debug with expensive value: ${DateTime.now()}',
  );

  await logger.flush();
  await logger.dispose();
}
