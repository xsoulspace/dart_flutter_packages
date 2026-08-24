import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Hybrid logical clock timestamp (ADR 0011 §2).
///
/// Total order: `(wallMillis, counter, actorId)`. The actorId tiebreak makes
/// the order total across replicas, which is what makes LWW convergence
/// deterministic regardless of delivery order.
@immutable
final class Hlc implements Comparable<Hlc> {
  factory Hlc.fromJson(final Map<String, dynamic> json) => Hlc(
    (json['w'] as num).toInt(),
    (json['c'] as num).toInt(),
    (json['a'] as String),
  );

  factory Hlc.fromString(final String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 3) {
      throw ArgumentError.value(encoded, 'encoded', 'Invalid HLC encoding');
    }
    return Hlc(int.parse(parts[0]), int.parse(parts[1]), parts[2]);
  }

  const Hlc(this.wallMillis, this.counter, this.actorId)
    : assert(wallMillis >= 0),
      assert(counter >= 0),
      assert(actorId != '');

  /// Zero timestamp for [actorId]; strictly less than any real event.
  static Hlc zero(final String actorId) => Hlc(0, 0, actorId);

  final int wallMillis;
  final int counter;
  final String actorId;

  /// Next local-event timestamp. Monotonic: never returns a value
  /// `<=` this, even when the wall clock regresses.
  Hlc tick(final DateTime now) => _next(now.millisecondsSinceEpoch, null);

  /// Next timestamp after receiving [remote]. Absorbs remote's wall clock
  /// (never trusts a lower one) and stays strictly above both inputs.
  Hlc receive(final Hlc remote, final DateTime now) {
    if (identical(remote, this)) {
      throw ArgumentError('Cannot receive own Hlc', 'remote');
    }
    return _next(now.millisecondsSinceEpoch, remote);
  }

  /// Returns a timestamp strictly greater than both this and [remote] (when
  /// non-null), anchored to the highest known wall clock.
  Hlc _next(final int wallNow, final Hlc? remote) {
    final maxWall = switch (remote) {
      null => math.max(wallNow, wallMillis),
      _ => math.max(wallNow, math.max(wallMillis, remote.wallMillis)),
    };
    if (remote == null || maxWall > remote.wallMillis) {
      if (maxWall > wallMillis) return Hlc(maxWall, 0, actorId);
      return Hlc(wallMillis, counter + 1, actorId);
    }
    // maxWall == remote.wallMillis: must also exceed remote's counter.
    if (maxWall > wallMillis) return Hlc(maxWall, remote.counter + 1, actorId);
    return Hlc(wallMillis, math.max(counter, remote.counter) + 1, actorId);
  }

  bool operator >(final Hlc other) => compareTo(other) > 0;
  bool operator <(final Hlc other) => compareTo(other) < 0;
  bool operator >=(final Hlc other) => compareTo(other) >= 0;
  bool operator <=(final Hlc other) => compareTo(other) <= 0;

  @override
  int compareTo(final Hlc other) {
    if (wallMillis != other.wallMillis) {
      return wallMillis.compareTo(other.wallMillis);
    }
    if (counter != other.counter) return counter.compareTo(other.counter);
    return actorId.compareTo(other.actorId);
  }

  Map<String, dynamic> toJson() => {
    'w': wallMillis,
    'c': counter,
    'a': actorId,
  };

  @override
  String toString() => '$wallMillis:$counter:$actorId';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is Hlc &&
          other.wallMillis == wallMillis &&
          other.counter == counter &&
          other.actorId == actorId);

  @override
  int get hashCode => Object.hash(wallMillis, counter, actorId);
}

/// Serializes/derializes HLCs inside JSON payloads.
Map<String, dynamic> hlcToJson(final Hlc hlc) => hlc.toJson();

Hlc hlcFromJson(final Object? raw) => raw is Map<String, dynamic>
    ? Hlc.fromJson(raw)
    : throw ArgumentError.value(raw, 'raw', 'Not an Hlc json map');

/// Restores a persisted last-issued timestamp so monotonicity survives
/// process restarts (ADR 0011 obligation).
Hlc hlcRestoreMonotonic({
  required final Hlc persistedLast,
  required final DateTime now,
}) {
  final wallNow = now.millisecondsSinceEpoch;
  if (wallNow > persistedLast.wallMillis) {
    return Hlc(wallNow, 0, persistedLast.actorId);
  }
  return persistedLast;
}
