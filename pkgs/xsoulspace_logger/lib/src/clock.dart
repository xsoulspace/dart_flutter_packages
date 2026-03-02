library;

/// Abstraction for deterministic time in tests.
abstract interface class Clock {
  DateTime nowUtc();
}

/// System-backed clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
