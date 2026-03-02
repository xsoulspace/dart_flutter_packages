# xsoulspace_logger_triage

Issue intelligence sink for
[`xsoulspace_logger`](https://pub.dev/packages/xsoulspace_logger).

`xsoulspace_logger_triage` groups repeated failures into issue fingerprints and
calculates priority scores for escalation.

## Features

- Fingerprinting from error type, normalized message, stack frames, and category.
- Token normalization for numbers/UUID/hex values.
- Dedup window support (default `10 minutes`).
- Issue status lifecycle: `open -> regressing -> resolved`.
- Priority scoring from severity + frequency + recency.
- Escalation when score threshold is reached or critical events occur.
- Streaming API for top issues.

## Installation

```yaml
dependencies:
  xsoulspace_logger: ^1.0.0-beta.0
  xsoulspace_logger_triage: ^1.0.0-beta.0
```

## Usage

```dart
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

Future<void> main() async {
  final triage = IssueTriageSink(
    config: const TriageConfig(
      dedupWindow: Duration(minutes: 10),
      escalationScoreThreshold: 70,
    ),
  );

  final logger = Logger(const LoggerConfig(), <LogSink>[triage]);

  logger.error('api', 'Request failed for user 123', error: Exception('HTTP 500'));
  logger.error('api', 'Request failed for user 456', error: Exception('HTTP 500'));

  await logger.flush();

  final topIssues = triage.currentTopIssues(limit: 10);
  for (final issue in topIssues) {
    print('${issue.fingerprint} score=${issue.priorityScore} escalated=${issue.escalated}');
  }

  await triage.markResolved(topIssues.first.fingerprint);
  await logger.dispose();
}
```

## APIs

- `IssueTriageSink.watchTopIssues({int limit = 50})`
- `IssueTriageSink.currentTopIssues({int limit = 50})`
- `IssueTriageSink.markResolved(String fingerprint)`
- `FingerprintGenerator.fingerprint(LogRecord)`

## License

MIT
