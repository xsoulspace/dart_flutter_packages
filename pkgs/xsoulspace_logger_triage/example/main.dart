import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

Future<void> main() async {
  final triage = IssueTriageSink();
  final logger = Logger(const LoggerConfig(), <LogSink>[triage]);

  logger.error('api', 'Request failed for user 123', error: Exception('500'));
  logger.error('api', 'Request failed for user 456', error: Exception('500'));

  await logger.flush();

  for (final issue in triage.currentTopIssues()) {
    print(
      'fingerprint=${issue.fingerprint} '
      'occurrences24h=${issue.occurrences24h} '
      'score=${issue.priorityScore.toStringAsFixed(2)}',
    );
  }

  await logger.dispose();
}
