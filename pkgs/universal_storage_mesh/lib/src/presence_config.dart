/// Presence cadence policy with named presets and invariants (ADR 0031
/// §5: adaptive cadence is policy-with-bounds, not free knobs).
///
/// - The invariant `ttl = ttlFactor × pingInterval` always holds: a peer
///   expires after ~[ttlFactor] missed pings (the ttl is the crash
///   backstop — a silent peer drops out of every fold without a leave).
/// - Cadence adapts to activity WITHIN the preset's bounds: fast actions
///   shorten the interval toward [minPingInterval], idleness relaxes it
///   toward [maxPingInterval] — never beyond the bounds.
/// - Constructor-level for apps/games; user-facing settings are a later,
///   separate product decision.
final class PresenceConfig {
  const PresenceConfig({
    required this.minPingInterval,
    required this.maxPingInterval,
    this.ttlFactor = defaultTtlFactor,
  }) : assert(ttlFactor >= 2, 'a peer must survive at least 2 missed pings');

  /// Games, live co-editing: short ping/ttl so presence tracks the
  /// session tightly.
  static const PresenceConfig interactive = PresenceConfig(
    minPingInterval: Duration(seconds: 2),
    maxPingInterval: Duration(seconds: 10),
  );

  /// Document viewing and background work: longer cadence, fewer frames.
  static const PresenceConfig background = PresenceConfig(
    minPingInterval: Duration(seconds: 15),
    maxPingInterval: Duration(seconds: 60),
  );

  /// Default expiry factor (ADR 0031 §5): a peer expires after ~3 missed
  /// pings.
  static const defaultTtlFactor = 3;

  /// Shortest cadence, reached under activity; the floor of the bounds.
  final Duration minPingInterval;

  /// Longest cadence, used when idle; the ceiling of the bounds.
  final Duration maxPingInterval;

  /// Expiry is [ttlFactor] × the live ping interval.
  final int ttlFactor;

  /// Cadence for the current activity state, within the preset bounds:
  /// [active] shortens the interval toward [minPingInterval]; idleness
  /// relaxes it toward [maxPingInterval] (ADR 0031 §5).
  Duration pingInterval({required final bool active}) {
    assert(_boundsAreValid, 'minPingInterval must not exceed maxPingInterval');
    return active ? minPingInterval : maxPingInterval;
  }

  /// The invariant (ADR 0031 §5): `ttl = ttlFactor × pingInterval`.
  Duration ttlFor(final Duration pingInterval) {
    assert(_boundsAreValid, 'minPingInterval must not exceed maxPingInterval');
    return Duration(milliseconds: pingInterval.inMilliseconds * ttlFactor);
  }

  /// Debug-time bound check; Duration ordering is not const-evaluable, so
  /// the constructor cannot assert it directly.
  bool get _boundsAreValid =>
      !minPingInterval.isNegative &&
      minPingInterval.inMicroseconds > 0 &&
      minPingInterval.inMicroseconds <= maxPingInterval.inMicroseconds;

  @override
  String toString() =>
      'PresenceConfig(min: $minPingInterval, max: $maxPingInterval, '
      'ttlFactor: $ttlFactor)';
}
