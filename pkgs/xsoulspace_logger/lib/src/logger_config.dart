
import 'clock.dart';
import 'log_level.dart';
import 'redaction_policy.dart';

/// Runtime behavior for [Logger].
final class LoggerConfig {
  const LoggerConfig({
    this.minLevel = LogLevel.info,
    this.flushInterval = const Duration(seconds: 1),
    this.flushBatchSize = 256,
    this.queueCapacity = 20000,
    final int? hardQueueCapacity,
    this.redaction = const RedactionPolicy(),
    this.historyCapacity = 50000,
    this.disposeTimeout = const Duration(seconds: 5),
    this.backpressureWarningInterval = const Duration(seconds: 30),
    this.clock = const SystemClock(),
  }) : hardQueueCapacity = hardQueueCapacity ?? (queueCapacity + 1000),
       assert(flushBatchSize > 0),
       assert(queueCapacity > 0),
       assert(historyCapacity > 0),
       assert(hardQueueCapacity == null || hardQueueCapacity > queueCapacity);

  final LogLevel minLevel;
  final Duration flushInterval;
  final int flushBatchSize;
  final int queueCapacity;
  final int hardQueueCapacity;
  final RedactionPolicy redaction;
  final int historyCapacity;
  final Duration disposeTimeout;
  final Duration backpressureWarningInterval;
  final Clock clock;
}
