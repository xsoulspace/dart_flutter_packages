library;

import 'log_record.dart';

/// Output target for log records.
abstract interface class LogSink {
  Future<void> init();
  void enqueue(LogRecord record);
  Future<void> flush();
  Future<void> dispose();
}
