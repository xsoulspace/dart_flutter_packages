import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'behavior_profile.dart';
import 'behavior_step.dart';
import 'timing.dart';

/// Descriptive statistics over a set of durations, in microseconds.
///
/// Numbers only — the audit contract never emits verdicts about humans
/// (ADR 0044 non-claims); scoring against a reference corpus is the
/// consumer's job.
@immutable
final class StatSummary {
  /// Creates a summary.
  const StatSummary({
    required this.count,
    required this.minUs,
    required this.meanUs,
    required this.maxUs,
    required this.stddevUs,
  });

  /// Builds a summary from samples.
  factory StatSummary.of(Iterable<int> samples) {
    final values = samples.toList(growable: false);
    if (values.isEmpty) return StatSummary.empty;
    var total = 0;
    var min = values.first;
    var max = values.first;
    for (final value in values) {
      total += value;
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final mean = total / values.length;
    var squared = 0.0;
    for (final value in values) {
      final delta = value - mean;
      squared += delta * delta;
    }
    return StatSummary(
      count: values.length,
      minUs: min,
      meanUs: mean,
      maxUs: max,
      stddevUs: values.length > 1
          ? math.sqrt(squared / (values.length - 1))
          : 0,
    );
  }

  /// Empty summary (count 0).
  static const StatSummary empty = StatSummary(
    count: 0,
    minUs: 0,
    meanUs: 0,
    maxUs: 0,
    stddevUs: 0,
  );

  /// Number of samples.
  final int count;

  /// Minimum sample, microseconds.
  final int minUs;

  /// Arithmetic mean, microseconds.
  final double meanUs;

  /// Maximum sample, microseconds.
  final int maxUs;

  /// Sample standard deviation, microseconds (`dart:math` sqrt is IEEE
  /// correctly-rounded, hence bit-stable).
  final double stddevUs;

  /// Coefficient of variation (stddev/mean); 0 without samples or mean.
  double get cv => meanUs == 0 ? 0 : stddevUs / meanUs;

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'count': count,
    'minUs': minUs,
    'meanUs': meanUs,
    'maxUs': maxUs,
    'stddevUs': stddevUs,
  };

  @override
  String toString() =>
      'StatSummary(n=$count, min=${minUs}us, '
      'mean=${meanUs.toStringAsFixed(0)}us, max=${maxUs}us)';
}

/// The audit report: descriptive numbers about a plan and its profile.
///
/// Self-consistency (plan vs declared distributions) and physical
/// plausibility (biomechanical ceilings) only. The library never scores
/// "human-likeness" — that requires a reference corpus the library does
/// not have (ADR 0044).
@immutable
final class BehaviorReport {
  /// Creates a report.
  const BehaviorReport({
    required this.profileHash,
    required this.planHash,
    required this.eventCount,
    required this.totalDurationUs,
    required this.dwells,
    required this.interStepGaps,
    required this.cadenceGaps,
    required this.moveCount,
    required this.pathLengthPx,
    required this.displacementPx,
    required this.maxSpeedPxPerSecond,
    required this.declaredVsObservedUs,
    required this.subFloorKeyGapCount,
    required this.overCeilingSpeedCount,
  });

  /// Wire/format identifier.
  static const String schemaId = 'behavior.report/v1';

  /// Biomechanical repeat floor for consecutive keystrokes (µs).
  static const int keyGapFloorUs = 20_000;

  /// Ceiling for synthesized pointer speed (px/s).
  static const double speedCeilingPxPerSecond = 20_000;

  /// Hash of the audited profile.
  final String profileHash;

  /// Hash of the audited plan.
  final String planHash;

  /// Number of steps in the plan.
  final int eventCount;

  /// Total planned duration, microseconds.
  final int totalDurationUs;

  /// Explicit dwell steps.
  final StatSummary dwells;

  /// Positive gaps between any two consecutive steps.
  final StatSummary interStepGaps;

  /// Gaps between consecutive key/char steps (cadence check).
  final StatSummary cadenceGaps;

  /// Number of pointer-move steps.
  final int moveCount;

  /// Total length of the pointer path, logical pixels.
  final double pathLengthPx;

  /// Straight-line distance from the first to the last move point.
  final double displacementPx;

  /// Fastest synthesized move segment, px/s.
  final double maxSpeedPxPerSecond;

  /// Observed minus declared mean, per checked facet: keys are facet
  /// paths (`rhythm.beforeAction`, `pointer.moveDuration`,
  /// `cadence.digraph`); values in microseconds. A facet with no
  /// observations is absent.
  final Map<String, double> declaredVsObservedUs;

  /// Key/char gaps below [keyGapFloorUs].
  final int subFloorKeyGapCount;

  /// Move segments above [speedCeilingPxPerSecond].
  final int overCeilingSpeedCount;

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'schema': schemaId,
    'profileHash': profileHash,
    'planHash': planHash,
    'eventCount': eventCount,
    'totalDurationUs': totalDurationUs,
    'dwells': dwells.toJson(),
    'interStepGaps': interStepGaps.toJson(),
    'cadenceGaps': cadenceGaps.toJson(),
    'moveCount': moveCount,
    'pathLengthPx': pathLengthPx,
    'displacementPx': displacementPx,
    'maxSpeedPxPerSecond': maxSpeedPxPerSecond,
    'declaredVsObservedUs': declaredVsObservedUs,
    'subFloorKeyGapCount': subFloorKeyGapCount,
    'overCeilingSpeedCount': overCeilingSpeedCount,
  };

  @override
  String toString() => 'BehaviorReport($eventCount events, '
      '$totalDurationUs us, flags: $subFloorKeyGapCount sub-floor, '
      '$overCeilingSpeedCount over-ceiling)';
}

/// Audits [plan] against [profile]: self-consistency deltas, structural
/// descriptives, and physical-plausibility flags. Pure; never throws on
/// plan shape, and never returns a humanness verdict.
BehaviorReport auditBehavior(BehaviorPlan plan, BehaviorProfile profile) {
  final steps = plan.steps;

  final dwellSamples = <int>[];
  final gapSamples = <int>[];
  final cadenceSamples = <int>[];
  final moveDurationSamples = <int>[];
  int? lastKeyCharAt;
  var subFloorKeyGaps = 0;

  var moveCount = 0;
  var pathLength = 0.0;
  var maxSpeed = 0.0;
  var overCeiling = 0;
  (double, double)? firstMove;
  (double, double)? lastMove;

  int? previousAt;
  for (final step in steps) {
    if (previousAt != null) {
      final gap = step.plannedAtUs - previousAt;
      if (gap > 0) gapSamples.add(gap);
    }
    previousAt = step.plannedAtUs;
    switch (step) {
      case DwellStep(:final durationUs):
        dwellSamples.add(durationUs);
      case PointerMoveStep(:final x, :final y, :final durationUs):
        final previous = lastMove;
        moveCount++;
        firstMove ??= (x, y);
        if (previous != null) {
          pathLength += _distance(previous.$1, previous.$2, x, y);
        }
        lastMove = (x, y);
        moveDurationSamples.add(durationUs);
        if (durationUs > 0 && previous != null) {
          final speed =
              _distance(previous.$1, previous.$2, x, y) /
              durationUs *
              1_000_000;
          if (speed > maxSpeed) maxSpeed = speed;
          if (speed > BehaviorReport.speedCeilingPxPerSecond) overCeiling++;
        }
      case KeyDownStep() || KeyUpStep() || CharStep():
        if (lastKeyCharAt != null) {
          final gap = step.plannedAtUs - lastKeyCharAt;
          if (gap > 0) {
            cadenceSamples.add(gap);
            if (gap < BehaviorReport.keyGapFloorUs) subFloorKeyGaps++;
          }
        }
        lastKeyCharAt = step.plannedAtUs;
      case PointerDownStep() || PointerUpStep() || WheelStep():
        break;
    }
  }

  double? declaredDelta(TimingDistribution declared, List<int> samples) =>
      samples.isEmpty ? null : _mean(samples) - declared.meanUs;

  final declaredVsObserved = <String, double>{
    if (dwellSamples.isNotEmpty)
      'rhythm.beforeAction':
          declaredDelta(profile.rhythm.beforeAction, dwellSamples)!,
    if (moveDurationSamples.isNotEmpty)
      'pointer.moveDuration':
          declaredDelta(profile.pointer.moveDuration, moveDurationSamples)!,
    if (cadenceSamples.isNotEmpty)
      'cadence.digraph':
          declaredDelta(profile.cadence.digraph, cadenceSamples)!,
  };

  final displacement = firstMove != null && lastMove != null
      ? _distance(firstMove.$1, firstMove.$2, lastMove.$1, lastMove.$2)
      : 0.0;

  return BehaviorReport(
    profileHash: profile.hash,
    planHash: plan.hash,
    eventCount: steps.length,
    totalDurationUs: plan.totalDurationUs,
    dwells: StatSummary.of(dwellSamples),
    interStepGaps: StatSummary.of(gapSamples),
    cadenceGaps: StatSummary.of(cadenceSamples),
    moveCount: moveCount,
    pathLengthPx: pathLength,
    displacementPx: displacement,
    maxSpeedPxPerSecond: maxSpeed,
    declaredVsObservedUs: declaredVsObserved,
    subFloorKeyGapCount: subFloorKeyGaps,
    overCeilingSpeedCount: overCeiling,
  );
}

double _mean(List<int> values) {
  var total = 0;
  for (final value in values) {
    total += value;
  }
  return total / values.length;
}

double _distance(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  return math.sqrt(dx * dx + dy * dy);
}
