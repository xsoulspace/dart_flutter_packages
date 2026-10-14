import '../clock.dart';

/// Mutable deterministic clock for tests.
final class FakeClock implements Clock {
  FakeClock(DateTime initialUtc) : _now = initialUtc.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void setUtc(DateTime utc) {
    _now = utc.toUtc();
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}
