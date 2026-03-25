import 'dart:io';

import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_io/xsoulspace_logger_io.dart';

Future<void> main() async {
  final sink = IoLogSink(
    IoLogSinkConfig(
      directoryPath: '${Directory.systemTemp.path}/logger_example',
    ),
  );

  final logger = Logger(const LoggerConfig(), <LogSink>[sink]);
  logger.info('example', 'Persisted to NDJSON segment files');

  await logger.flush();
  await logger.dispose();
}
