
import 'package:test/test.dart';
import 'package:xsoulspace_logger/testing.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

void main() {
  group('Logger core behavior', () {
    test('filters disabled levels before lazy message work', () async {
      final sink = InMemoryLogSink();
      final logger = Logger(
        const LoggerConfig(
          minLevel: LogLevel.warning,
          flushInterval: Duration(hours: 1),
        ),
        <LogSink>[sink],
      );

      var built = false;
      logger.debugLazy('lazy', () {
        built = true;
        return 'expensive';
      });

      await logger.flush();

      expect(built, isFalse);
      expect(sink.records, isEmpty);
      await logger.dispose();
    });

    test(
      'redacts sensitive fields and enforces depth and size guards',
      () async {
        final sink = InMemoryLogSink();
        final logger = Logger(
          const LoggerConfig(flushInterval: Duration(hours: 1)),
          <LogSink>[sink],
        );

        logger.info(
          'security',
          'payload',
          fields: <String, Object?>{
            'password': 'secret',
            'profile': <String, Object?>{
              'email': 'user@example.com',
              'token': 'abcdef',
            },
            'deep': <String, Object?>{
              'a': <String, Object?>{
                'b': <String, Object?>{
                  'c': <String, Object?>{
                    'd': <String, Object?>{
                      'e': <String, Object?>{
                        'f': <String, Object?>{'g': 'value'},
                      },
                    },
                  },
                },
              },
            },
            'blob': 'x' * 5000,
          },
        );

        await logger.flush();

        final record = sink.records.single;
        expect(record.fields['password'], '[REDACTED]');

        final profile = record.fields['profile']! as Map<String, Object?>;
        expect(profile['email'], '[REDACTED]');
        expect(profile['token'], '[REDACTED]');

        final blob = record.fields['blob']! as String;
        expect(blob, contains('[TRUNCATED]'));
        expect(record.fields.toString(), contains('[MAX_DEPTH]'));

        await logger.dispose();
      },
    );

    test('drops low-priority records first under backpressure', () async {
      final clock = FakeClock(DateTime.utc(2026));
      final sink = InMemoryLogSink();
      final logger = Logger(
        LoggerConfig(
          minLevel: LogLevel.trace,
          flushInterval: const Duration(hours: 1),
          flushBatchSize: 64,
          queueCapacity: 2,
          hardQueueCapacity: 4,
          clock: clock,
        ),
        <LogSink>[sink],
      );

      logger.traceLog('flow', 'trace');
      logger.debug('flow', 'debug');
      logger.warning('flow', 'warning');
      logger.error('flow', 'error');

      await logger.flush();

      expect(sink.records.any((final r) => r.level == LogLevel.trace), isFalse);
      expect(sink.records.any((final r) => r.level == LogLevel.debug), isFalse);
      expect(
        sink.records.any((final r) => r.level == LogLevel.warning),
        isTrue,
      );
      expect(sink.records.any((final r) => r.level == LogLevel.error), isTrue);
      expect(
        sink.records.any(
          (final r) => r.category == LoggerCategories.backpressure,
        ),
        isTrue,
      );

      await logger.dispose();
    });

    test('trace query returns ordered chain', () async {
      final sink = InMemoryLogSink();
      final logger = Logger(
        const LoggerConfig(flushInterval: Duration(hours: 1)),
        <LogSink>[sink],
      );

      const trace = TraceContext(traceId: 'trace-1', spanId: 'span-a');
      final traced = logger.child(
        trace: trace,
        fields: <String, Object?>{'session': 'abc'},
      );

      traced.info('checkout', 'start');
      traced.warning('checkout', 'retry');
      traced.error('checkout', 'failed');

      await logger.flush();

      final chain = await logger.trace('trace-1');
      expect(chain.length, 3);
      expect(chain.every((final r) => r.trace?.traceId == 'trace-1'), isTrue);
      expect(chain[0].sequence < chain[1].sequence, isTrue);
      expect(chain[1].sequence < chain[2].sequence, isTrue);

      await logger.dispose();
    });

    test('watch and query apply filters', () async {
      final sink = InMemoryLogSink();
      final logger = Logger(
        const LoggerConfig(flushInterval: Duration(hours: 1)),
        <LogSink>[sink],
      );

      final errorFuture = logger
          .watch(const LogQuery(levels: <LogLevel>{LogLevel.error}))
          .first;

      logger.info('api', 'ok');
      logger.error('api', 'boom', fields: <String, Object?>{'code': 500});

      await logger.flush();

      final watchedError = await errorFuture;
      expect(watchedError.level, LogLevel.error);

      final queried = await logger.query(const LogQuery(text: 'boom'));
      expect(queried.length, 1);
      expect(queried.single.category, 'api');

      await logger.dispose();
    });

    test(
      'regression: dispose flushes pending records before closing sinks',
      () async {
        final sink = InMemoryLogSink();
        final logger = Logger(
          const LoggerConfig(flushInterval: Duration(hours: 1)),
          <LogSink>[sink],
        );

        logger.info('regression', 'must survive dispose');
        await logger.dispose();

        expect(sink.records.length, 1);
        expect(sink.records.single.message, 'must survive dispose');
        expect(sink.flushCount, greaterThanOrEqualTo(1));
        expect(sink.disposed, isTrue);
      },
    );
  });
}
