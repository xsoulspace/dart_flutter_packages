library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

void main() {
  group('FingerprintGenerator', () {
    test('normalizes volatile tokens and frame line numbers', () {
      final generator = FingerprintGenerator();
      final baseTime = DateTime.utc(2026, 1, 1, 12);

      final recordA = LogRecord(
        sequence: 1,
        timestampUtc: baseTime,
        level: LogLevel.error,
        category: 'auth',
        message:
            'User 123 failed for request 550e8400-e29b-41d4-a716-446655440000 '
            'with token 0xABCDEF123456',
        error: StateError('bad state'),
        stackTrace: StackTrace.fromString(
          '#0 AuthService.login (package:app/auth.dart:11:7)\n'
          '#1 _RootZone.runUnary (dart:async/zone.dart:1200:1)',
        ),
      );

      final recordB = LogRecord(
        sequence: 2,
        timestampUtc: baseTime.add(const Duration(seconds: 1)),
        level: LogLevel.error,
        category: 'auth',
        message:
            'User 999 failed for request f47ac10b-58cc-4372-a567-0e02b2c3d479 '
            'with token 0x1234567890AB',
        error: StateError('bad state'),
        stackTrace: StackTrace.fromString(
          '#0 AuthService.login (package:app/auth.dart:99:3)\n'
          '#1 _RootZone.runUnary (dart:async/zone.dart:1300:4)',
        ),
      );

      final fingerprintA = generator.fingerprint(recordA);
      final fingerprintB = generator.fingerprint(recordB);

      expect(fingerprintA, fingerprintB);
    });
  });

  group('IssueTriageSink', () {
    test(
      'deduplicates by fingerprint and transitions resolved to regressing',
      () async {
        final sink = IssueTriageSink(
          config: const TriageConfig(dedupWindow: Duration(minutes: 10)),
        );
        await sink.init();

        final base = DateTime.utc(2026, 1, 1, 10);
        sink.enqueue(
          _record(
            sequence: 1,
            at: base,
            level: LogLevel.error,
            message: 'Database timeout for user 1',
          ),
        );
        sink.enqueue(
          _record(
            sequence: 2,
            at: base.add(const Duration(minutes: 5)),
            level: LogLevel.error,
            message: 'Database timeout for user 2',
          ),
        );

        final afterDuplicates = sink.currentTopIssues();
        expect(afterDuplicates.length, 1);
        expect(afterDuplicates.single.occurrences24h, 2);
        expect(afterDuplicates.single.status, IssueStatus.open);

        final fingerprint = afterDuplicates.single.fingerprint;
        await sink.markResolved(fingerprint);
        expect(sink.currentTopIssues().single.status, IssueStatus.resolved);

        sink.enqueue(
          _record(
            sequence: 3,
            at: base.add(const Duration(minutes: 20)),
            level: LogLevel.error,
            message: 'Database timeout for user 3',
          ),
        );

        final afterRegression = sink.currentTopIssues();
        expect(afterRegression.single.status, IssueStatus.regressing);
        expect(afterRegression.single.occurrences24h, 3);

        await sink.dispose();
      },
    );

    test('escalates by score threshold and for critical level', () async {
      final sink = IssueTriageSink();
      await sink.init();

      final base = DateTime.now().toUtc();
      for (var i = 0; i < 30; i++) {
        sink.enqueue(
          _record(
            sequence: i + 1,
            at: base.add(Duration(seconds: i)),
            level: LogLevel.warning,
            category: 'network',
            message: 'Retry failed for endpoint /v1/items/$i',
          ),
        );
      }

      final issues = sink.currentTopIssues();
      expect(issues, isNotEmpty);
      expect(issues.first.escalated, isTrue);
      expect(issues.first.priorityScore, greaterThanOrEqualTo(70));

      sink.enqueue(
        _record(
          sequence: 1000,
          at: base.add(const Duration(minutes: 1)),
          level: LogLevel.critical,
          category: 'kernel',
          message: 'Kernel panic',
        ),
      );

      final updated = sink.currentTopIssues();
      final criticalIssue = updated.firstWhere(
        (final issue) => issue.highestLevel == LogLevel.critical,
      );
      expect(criticalIssue.escalated, isTrue);

      await sink.dispose();
    });

    test('watchTopIssues streams sorted updates', () async {
      final sink = IssueTriageSink();
      await sink.init();

      final completer = Completer<List<IssueGroup>>();
      final subscription = sink.watchTopIssues(limit: 1).listen((final groups) {
        if (groups.isNotEmpty && !completer.isCompleted) {
          completer.complete(groups);
        }
      });
      addTearDown(subscription.cancel);

      sink.enqueue(
        _record(
          sequence: 1,
          at: DateTime.now().toUtc(),
          level: LogLevel.error,
          category: 'api',
          message: 'request failed 500',
        ),
      );

      final top = await completer.future.timeout(const Duration(seconds: 5));
      expect(top.length, 1);
      expect(top.single.highestLevel, LogLevel.error);

      await sink.dispose();
    });
  });
}

LogRecord _record({
  required final int sequence,
  required final DateTime at,
  required final LogLevel level,
  final String category = 'db',
  required final String message,
}) => LogRecord(
  sequence: sequence,
  timestampUtc: at.toUtc(),
  level: level,
  category: category,
  message: message,
  error: Exception(message),
  stackTrace: StackTrace.fromString(
    '#0 Repository.load (package:app/repository.dart:10:3)\n'
    '#1 _RootZone.runUnary (dart:async/zone.dart:1000:2)',
  ),
);
