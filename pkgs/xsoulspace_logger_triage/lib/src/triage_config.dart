
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

/// Runtime behavior for issue triage.
final class TriageConfig {
  const TriageConfig({
    this.dedupWindow = const Duration(minutes: 10),
    this.occurrenceWindow = const Duration(hours: 24),
    this.topAppFrames = 5,
    this.escalationScoreThreshold = 70,
  }) : assert(topAppFrames > 0),
       assert(escalationScoreThreshold >= 0);

  final Duration dedupWindow;
  final Duration occurrenceWindow;
  final int topAppFrames;
  final double escalationScoreThreshold;

  /// Weight contribution by highest observed level.
  int severityWeight(final LogLevel level) => switch (level) {
    LogLevel.critical => 70,
    LogLevel.error => 50,
    LogLevel.warning => 25,
    LogLevel.info => 5,
    LogLevel.debug => 1,
    LogLevel.trace => 0,
  };
}
