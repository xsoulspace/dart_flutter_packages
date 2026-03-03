import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_crashhunter/analytics/analytics.dart';

void main() {
  group('convertErrorDetailsToString', () {
    test('includes reason, fatal marker, and exception details', () {
      final details = convertErrorDetailsToString(
        StateError('boom'),
        StackTrace.empty,
        reason: 'during test',
        fatal: true,
        information: const <DiagnosticsNode>[
          StringProperty('context', 'unit-test'),
        ],
      );

      expect(details, contains('FATAL'));
      expect(details, contains('during test'));
      expect(details, contains('Bad state: boom'));
      expect(details, contains('context: unit-test'));
    });
  });

  group('AnalyticsServiceImpl', () {
    test('forwards analytic events and intended exceptions to plugins',
        () async {
      final plugin = _FakeAnalyticsPlugin();
      final service = AnalyticsServiceImpl();
      service.upsertPlugin<_FakeAnalyticsPlugin>(plugin);

      await service.logAnalyticEvent(AnalyticEvents.usedInWeb);
      service.reportIntededException('known issue');

      expect(plugin.loggedEvents, <AnalyticEvents>[AnalyticEvents.usedInWeb]);
      expect(plugin.intendedExceptions, <Object?>['known issue']);
    });
  });
}

final class _FakeAnalyticsPlugin extends AnalyticsServicePlugin {
  final List<AnalyticEvents> loggedEvents = <AnalyticEvents>[];
  final List<Object?> intendedExceptions = <Object?>[];

  @override
  Future<void> logAnalyticEvent(final AnalyticEvents event) async {
    loggedEvents.add(event);
  }

  @override
  Future<void> onDelayedLoad() async {}

  @override
  Future<void> onLoad() async {}

  @override
  void reportIntededException([final dynamic value]) {
    intendedExceptions.add(value);
  }

  @override
  Future<void> recordError(
    final dynamic exception,
    final StackTrace? stack, {
    final dynamic reason,
    final Iterable<DiagnosticsNode> information = const <DiagnosticsNode>[],
    final bool fatal = false,
    final bool? printDetails,
  }) async {}

  @override
  Future<void> recordFlutterError(
    final FlutterErrorDetails flutterErrorDetails, {
    final bool fatal = false,
  }) async {}
}
