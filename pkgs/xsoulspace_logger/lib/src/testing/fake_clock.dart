library;

import '../clock.dart';

/// Mutable deterministic clock for tests.
final class FakeClock implements Clock {
  FakeClock(final DateTime initialUtc) : _now = initialUtc.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void setUtc(final DateTime utc) {
    _now = utc.toUtc();
  }

  void advance(final Duration duration) {
    _now = _now.add(duration);
  }
}
