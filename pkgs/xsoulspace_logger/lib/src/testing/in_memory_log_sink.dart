library;

import '../log_record.dart';
import '../log_sink.dart';

/// Test sink that captures records in memory.
final class InMemoryLogSink implements LogSink {
  InMemoryLogSink({this.onEnqueue, this.onFlush, this.onDispose});

  final void Function(LogRecord record)? onEnqueue;
  final Future<void> Function()? onFlush;
  final Future<void> Function()? onDispose;

  final List<LogRecord> records = <LogRecord>[];

  bool initialized = false;
  int flushCount = 0;
  bool disposed = false;

  @override
  Future<void> init() async {
    initialized = true;
  }

  @override
  void enqueue(final LogRecord record) {
    records.add(record);
    onEnqueue?.call(record);
  }

  @override
  Future<void> flush() async {
    flushCount++;
    await onFlush?.call();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await onDispose?.call();
  }
}
