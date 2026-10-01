import 'package:meta/meta.dart';

import '../automation_spec.dart';
import 'behavior_rng.dart';

/// A timing distribution over durations, in integer microseconds.
///
/// Distributions are **sealed data with const constructors** — never
/// closures — so profiles holding them are `const`-able, comparable, and
/// serializable, and sampling is pure integer/rational arithmetic with no
/// transcendental functions (ADR 0044 determinism rules).
sealed class TimingDistribution extends TypedSpec {
  /// Creates a distribution.
  const TimingDistribution();

  /// Deserializes a distribution from its canonical JSON shape.
  factory TimingDistribution.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'fixed' => FixedTiming(micros: json['micros']! as int),
        'uniform' => UniformTiming(
          minMicros: json['minMicros']! as int,
          maxMicros: json['maxMicros']! as int,
        ),
        'piecewise' => PiecewiseTiming(
          boundariesUs: (json['boundariesUs']! as List<Object?>)
              .whereType<int>()
              .toList(growable: false),
        ),
        final other => throw FormatException(
          'unknown TimingDistribution kind "$other"',
        ),
      };

  /// Draws one duration in microseconds.
  int sample(BehaviorRng rng);

  /// Arithmetic mean in microseconds (declared, not observed).
  int get meanUs;

  /// Canonical JSON shape; kind-tagged.
  Map<String, Object?> toJson();
}

/// A constant duration.
@immutable
final class FixedTiming extends TimingDistribution {
  /// Creates a constant duration of [micros].
  const FixedTiming({required this.micros});

  /// The duration, in microseconds.
  final int micros;

  @override
  List<String> validate() => [
    if (micros < 0) 'FixedTiming.micros must be >= 0 (got $micros)',
  ];

  @override
  int sample(BehaviorRng rng) => micros;

  @override
  int get meanUs => micros;

  @override
  Map<String, Object?> toJson() => {'kind': 'fixed', 'micros': micros};

  @override
  bool operator ==(Object other) =>
      other is FixedTiming && other.micros == micros;

  @override
  int get hashCode => micros.hashCode;

  @override
  String toString() => 'FixedTiming(${micros}us)';
}

/// A uniform duration over `[minMicros, maxMicros)`.
@immutable
final class UniformTiming extends TimingDistribution {
  /// Creates a uniform distribution.
  const UniformTiming({required this.minMicros, required this.maxMicros});

  /// Inclusive lower bound, in microseconds.
  final int minMicros;

  /// Exclusive upper bound, in microseconds.
  final int maxMicros;

  @override
  List<String> validate() {
    final violations = <String>[
      if (minMicros < 0)
        'UniformTiming.minMicros must be >= 0 (got $minMicros)',
    ];
    if (maxMicros < minMicros) {
      final message = 'UniformTiming.maxMicros ($maxMicros) must be '
          '>= minMicros ($minMicros)';
      violations.add(message);
    }
    return violations;
  }

  @override
  int sample(BehaviorRng rng) =>
      minMicros + (rng.nextUnit() * (maxMicros - minMicros)).floor();

  @override
  int get meanUs => ((minMicros + maxMicros) / 2).floor();

  @override
  Map<String, Object?> toJson() => {
    'kind': 'uniform',
    'minMicros': minMicros,
    'maxMicros': maxMicros,
  };

  @override
  bool operator ==(Object other) =>
      other is UniformTiming &&
      other.minMicros == minMicros &&
      other.maxMicros == maxMicros;

  @override
  int get hashCode => Object.hash(minMicros, maxMicros);

  @override
  String toString() => 'UniformTiming($minMicros..$maxMicros us)';
}

/// An empirical distribution: `n` equal-probability buckets delimited by
/// `n + 1` strictly increasing boundaries; sampling is uniform bucket pick
/// plus linear interpolation.
///
/// This is the v0.1 stand-in for measured (e.g. lognormal-like) human
/// cadence: quantile boundaries precomputed from reference data keep
/// sampling transcendental-free.
@immutable
final class PiecewiseTiming extends TimingDistribution {
  /// Creates an empirical distribution from [boundariesUs].
  const PiecewiseTiming({required this.boundariesUs});

  /// `n + 1` strictly increasing boundaries in microseconds.
  final List<int> boundariesUs;

  @override
  List<String> validate() {
    final violations = <String>[];
    if (boundariesUs.length < 2) {
      final message = 'PiecewiseTiming needs >= 2 boundaries '
          '(got ${boundariesUs.length})';
      violations.add(message);
    }
    if (boundariesUs.isNotEmpty && boundariesUs.first < 0) {
      final message = 'PiecewiseTiming boundaries must be >= 0 '
          '(first is ${boundariesUs.first})';
      violations.add(message);
    }
    for (var i = 1; i < boundariesUs.length; i++) {
      if (boundariesUs[i] <= boundariesUs[i - 1]) {
        final message = 'PiecewiseTiming boundaries must strictly '
            'increase (${boundariesUs[i - 1]} !< ${boundariesUs[i]})';
        violations.add(message);
      }
    }
    return violations;
  }

  @override
  int sample(BehaviorRng rng) {
    final buckets = boundariesUs.length - 1;
    final unit = rng.nextUnit();
    var index = (unit * buckets).floor();
    if (index >= buckets) index = buckets - 1;
    final lower = boundariesUs[index];
    final upper = boundariesUs[index + 1];
    final fraction = unit * buckets - index;
    return lower + (fraction * (upper - lower)).floor();
  }

  @override
  int get meanUs {
    var total = 0;
    for (var i = 0; i + 1 < boundariesUs.length; i++) {
      total += (boundariesUs[i] + boundariesUs[i + 1]) ~/ 2;
    }
    return total ~/ (boundariesUs.length - 1);
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'piecewise',
    'boundariesUs': boundariesUs,
  };

  @override
  bool operator ==(Object other) =>
      other is PiecewiseTiming &&
      _listEquals(other.boundariesUs, boundariesUs);

  @override
  int get hashCode => Object.hashAll(boundariesUs);

  @override
  String toString() => 'PiecewiseTiming($boundariesUs)';
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
