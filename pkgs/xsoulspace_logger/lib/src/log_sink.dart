
import 'log_record.dart';

/// Output target for log records.
abstract interface class LogSink {
  Future<void> init();
  void enqueue(final LogRecord record);
  Future<void> flush();
  Future<void> dispose();
}
