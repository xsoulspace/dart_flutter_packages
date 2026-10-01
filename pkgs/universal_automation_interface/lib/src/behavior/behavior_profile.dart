import 'package:meta/meta.dart';

import '../automation_exceptions.dart';
import '../automation_spec.dart';
import '../snapshot.dart';
import 'behavior_rng.dart';
import 'canonical.dart';
import 'timing.dart';

/// How the pointer travels: the path *shape* over a move segment.
sealed class PathModel extends TypedSpec {
  /// Creates a path model.
  const PathModel();

  /// Deserializes a path model from its canonical JSON shape.
  factory PathModel.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'direct' => const DirectPath(),
        'bezier' => BezierPath(
          curvature: (json['curvature']! as int) / 100.0,
          overshootPx: (json['overshootGrid']! as int) / 100.0,
        ),
        final other => throw FormatException('unknown PathModel "$other"'),
      };

  /// Canonical JSON shape; kind-tagged.
  Map<String, Object?> toJson();
}

/// Straight-line interpolation between path endpoints.
@immutable
final class DirectPath extends PathModel {
  /// Creates a direct path.
  const DirectPath();

  @override
  List<String> validate() => const [];

  @override
  Map<String, Object?> toJson() => {'kind': 'direct'};

  @override
  bool operator ==(Object other) => other is DirectPath;

  @override
  int get hashCode => 'direct'.hashCode;

  @override
  String toString() => 'DirectPath()';
}

/// A single-arc curve: the control point is offset perpendicular to the
/// straight line by `curvature * distance`, optionally overshooting the
/// target along the direction of travel and correcting back.
///
/// Sampling uses only `+ - * /` and `sqrt` (de Casteljau), per the ADR
/// 0044 determinism rules.
@immutable
final class BezierPath extends PathModel {
  /// Creates a curved path.
  const BezierPath({required this.curvature, required this.overshootPx});

  /// Perpendicular control-point offset as a fraction of travel distance;
  /// sign picks the side. Keep |curvature| in `[0, 0.5]`.
  final double curvature;

  /// Distance in logical pixels to travel past the target before the
  /// corrective return move; `0` disables overshoot.
  final double overshootPx;

  @override
  List<String> validate() {
    final violations = <String>[];
    if (curvature.abs() > 0.5) {
      final message = 'BezierPath.curvature must satisfy '
          '|curvature| <= 0.5 (got $curvature)';
      violations.add(message);
    }
    if (overshootPx < 0 || overshootPx > 64) {
      final message = 'BezierPath.overshootPx must be within '
          '[0, 64] px (got $overshootPx)';
      violations.add(message);
    }
    return violations;
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'bezier',
    'curvature': gridValue(curvature),
    'overshootGrid': gridValue(overshootPx),
  };

  @override
  bool operator ==(Object other) =>
      other is BezierPath &&
      other.curvature == curvature &&
      other.overshootPx == overshootPx;

  @override
  int get hashCode => Object.hash(curvature, overshootPx);

  @override
  String toString() =>
      'BezierPath(curvature: $curvature, overshootPx: $overshootPx)';
}

/// Pointer delivery dynamics: path shape, per-move duration, button hold,
/// and the maximum stride between synthesized move points.
@immutable
final class PointerMotion extends TypedSpec {
  /// Creates a pointer-motion facet.
  const PointerMotion({
    this.path = const DirectPath(),
    this.moveDuration = const FixedTiming(micros: 0),
    this.buttonHold = const FixedTiming(micros: 0),
    this.maxStepPx = 24,
  });

  /// Deserializes the facet from its canonical JSON shape.
  factory PointerMotion.fromJson(Map<String, Object?> json) => PointerMotion(
    path: PathModel.fromJson(json['path']! as Map<String, Object?>),
    moveDuration: TimingDistribution.fromJson(
      json['moveDuration']! as Map<String, Object?>,
    ),
    buttonHold: TimingDistribution.fromJson(
      json['buttonHold']! as Map<String, Object?>,
    ),
    maxStepPx: json['maxStepPx']! as int,
  );

  /// Travel shape between path endpoints.
  final PathModel path;

  /// Duration of each synthesized move segment.
  final TimingDistribution moveDuration;

  /// Time the button stays down between down and up.
  final TimingDistribution buttonHold;

  /// Maximum distance in logical pixels between consecutive move points;
  /// longer gestures are sampled more densely.
  final int maxStepPx;

  @override
  List<String> validate() => [
    ...path.validate(),
    ...moveDuration.validate(),
    ...buttonHold.validate(),
    if (maxStepPx < 1 || maxStepPx > 200)
      'PointerMotion.maxStepPx must be within [1, 200] px (got $maxStepPx)',
  ];

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'path': path.toJson(),
    'moveDuration': moveDuration.toJson(),
    'buttonHold': buttonHold.toJson(),
    'maxStepPx': maxStepPx,
  };

  @override
  bool operator ==(Object other) =>
      other is PointerMotion &&
      other.path == path &&
      other.moveDuration == moveDuration &&
      other.buttonHold == buttonHold &&
      other.maxStepPx == maxStepPx;

  @override
  int get hashCode => Object.hash(path, moveDuration, buttonHold, maxStepPx);

  @override
  String toString() => 'PointerMotion($path, $moveDuration)';
}

/// Keyboard delivery dynamics: inter-key (digraph) latency and key hold.
@immutable
final class KeystrokeCadence extends TypedSpec {
  /// Creates a keystroke-cadence facet.
  const KeystrokeCadence({
    this.digraph = const FixedTiming(micros: 0),
    this.hold = const FixedTiming(micros: 0),
  });

  /// Deserializes the facet from its canonical JSON shape.
  factory KeystrokeCadence.fromJson(Map<String, Object?> json) =>
      KeystrokeCadence(
        digraph: TimingDistribution.fromJson(
          json['digraph']! as Map<String, Object?>,
        ),
        hold: TimingDistribution.fromJson(
          json['hold']! as Map<String, Object?>,
        ),
      );

  /// Gap between consecutive keystrokes.
  final TimingDistribution digraph;

  /// Time a key stays down between down and up.
  final TimingDistribution hold;

  @override
  List<String> validate() => [
    ...digraph.validate(),
    ...hold.validate(),
  ];

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'digraph': digraph.toJson(),
    'hold': hold.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is KeystrokeCadence &&
      other.digraph == digraph &&
      other.hold == hold;

  @override
  int get hashCode => Object.hash(digraph, hold);

  @override
  String toString() => 'KeystrokeCadence($digraph, $hold)';
}

/// Pre-action dwell: how long the input source rests before an action.
@immutable
final class ActionRhythm extends TypedSpec {
  /// Creates an action-rhythm facet.
  const ActionRhythm({this.beforeAction = const FixedTiming(micros: 0)});

  /// Deserializes the facet from its canonical JSON shape.
  factory ActionRhythm.fromJson(Map<String, Object?> json) => ActionRhythm(
    beforeAction: TimingDistribution.fromJson(
      json['beforeAction']! as Map<String, Object?>,
    ),
  );

  /// Dwell before each dispatched action.
  final TimingDistribution beforeAction;

  @override
  List<String> validate() => beforeAction.validate();

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'beforeAction': beforeAction.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is ActionRhythm && other.beforeAction == beforeAction;

  @override
  int get hashCode => beforeAction.hashCode;

  @override
  String toString() => 'ActionRhythm($beforeAction)';
}

/// The observation→dispatch floor.
///
/// Behavioral gates measure "snapshot observed → action dispatched"; an
/// agent firing milliseconds after observing is the canonical automated
/// tell. The **driver enforces the floor** against its last observation
/// timestamp; the calling loop owns its real (upper) latency. Layered on
/// top of [ActionRhythm] — the effective lead is the larger of the two.
@immutable
final class ReactionDelay extends TypedSpec {
  /// Creates a reaction-delay facet.
  const ReactionDelay({this.floorUs = 0});

  /// Deserializes the facet from its canonical JSON shape.
  factory ReactionDelay.fromJson(Map<String, Object?> json) =>
      ReactionDelay(floorUs: json['floorUs']! as int);

  /// Minimum microseconds between the driver's last observation and the
  /// first dispatched event. `0` disables the floor.
  final int floorUs;

  @override
  List<String> validate() => [
    if (floorUs < 0 || floorUs > 10_000_000)
      'ReactionDelay.floorUs must be within [0, 10s] (got $floorUs)',
  ];

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {'floorUs': floorUs};

  @override
  bool operator ==(Object other) =>
      other is ReactionDelay && other.floorUs == floorUs;

  @override
  int get hashCode => floorUs.hashCode;

  @override
  String toString() => 'ReactionDelay(${floorUs}us floor)';
}

/// Session-level pacing: noise-event rate and rhythm drift.
///
/// Detectors weight cross-action statistics — a session of per-action
/// perfect behaviors stitched with metronomic gaps is a sequence-level
/// flag regardless of per-action quality. Both parameters are declared
/// data; v1 transports may refuse non-zero values loudly rather than
/// degrade (see the driver's capability contract).
@immutable
final class SessionPacing extends TypedSpec {
  /// Creates a session-pacing facet.
  const SessionPacing({this.noiseEventRate = 0, this.driftPerHourUs = 0});

  /// Deserializes the facet from its canonical JSON shape.
  factory SessionPacing.fromJson(Map<String, Object?> json) => SessionPacing(
    noiseEventRate: pixelsFromGrid(json['noiseEventGrid']! as int),
    driftPerHourUs: json['driftPerHourUs']! as int,
  );

  /// Probability `[0, 1]` that a goal action is preceded by a stray
  /// micro-move (small random offset and back).
  final double noiseEventRate;

  /// Additive trend in microseconds/hour applied to rhythm samples across
  /// a session (warmup/fatigue shaping).
  final int driftPerHourUs;

  @override
  List<String> validate() {
    final violations = <String>[];
    if (noiseEventRate < 0 || noiseEventRate > 1) {
      final message = 'SessionPacing.noiseEventRate must be within '
          '[0, 1] (got $noiseEventRate)';
      violations.add(message);
    }
    if (driftPerHourUs.abs() > 3_600_000_000) {
      const message = 'SessionPacing.driftPerHourUs exceeds ±1h/h';
      violations.add(message);
    }
    return violations;
  }

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'noiseEventGrid': gridValue(noiseEventRate),
    'driftPerHourUs': driftPerHourUs,
  };

  @override
  bool operator ==(Object other) =>
      other is SessionPacing &&
      other.noiseEventRate == noiseEventRate &&
      other.driftPerHourUs == driftPerHourUs;

  @override
  int get hashCode => Object.hash(noiseEventRate, driftPerHourUs);

  @override
  String toString() =>
      'SessionPacing(noise: $noiseEventRate, drift: $driftPerHourUs us/h)';
}

/// A declarative input-dynamics profile: how actions are delivered.
///
/// Pure data — serializable, hashable, comparable, validated at
/// construction so an invalid profile is not constructible. Humans and
/// agents are both points in this space; nothing in the contract treats
/// either as the default (ADR 0044).
@immutable
final class BehaviorProfile extends TypedSpec {

  /// Creates and validates a profile.
  factory BehaviorProfile({
    ActionRhythm rhythm = const ActionRhythm(),
    ReactionDelay reaction = const ReactionDelay(),
    SessionPacing pacing = const SessionPacing(),
    PointerMotion pointer = const PointerMotion(),
    KeystrokeCadence cadence = const KeystrokeCadence(),
  }) => BehaviorProfile._(rhythm, reaction, pacing, pointer, cadence)
      ..ensureValid();

  /// Samples a per-session human-prior profile from broad ranges.
  ///
  /// This is deliberately **not** a shared constant: a single fixed
  /// human-like distribution used by every caller would itself be a
  /// cohort fingerprint. The prior draws each session's parameters from
  /// wide intervals so cross-session similarity is "broadly human", not
  /// "this library". Cadence tables below are shaped from published
  /// keystroke-dynamics literature and are placeholders pending measured
  /// reference data — the library does not claim human-likeness (see the
  /// ADR non-claims).
  ///
  /// Seeds are session-sensitive: deterministic seeds are for tests/CI;
  /// production sessions draw fresh entropy and never log or reuse seeds.
  factory BehaviorProfile.humanPrior(int seed) {
    final rng = BehaviorRng(seed);
    return BehaviorProfile(
      rhythm: ActionRhythm(
        beforeAction: UniformTiming(
          minMicros: rng.nextBetween(120_000, 260_000),
          maxMicros: rng.nextBetween(650_000, 1_500_000),
        ),
      ),
      reaction: ReactionDelay(floorUs: rng.nextBetween(160_000, 420_000)),
      pointer: PointerMotion(
        path: BezierPath(
          curvature: (rng.nextUnit() * 2 - 1) * 0.16,
          overshootPx: rng.nextUnit() * 12,
        ),
        moveDuration: UniformTiming(
          minMicros: rng.nextBetween(110_000, 240_000),
          maxMicros: rng.nextBetween(380_000, 850_000),
        ),
        buttonHold: const UniformTiming(minMicros: 55_000, maxMicros: 165_000),
      ),
      cadence: KeystrokeCadence(
        digraph: PiecewiseTiming(boundariesUs: _scaledDigraph(rng)),
        hold: const UniformTiming(minMicros: 42_000, maxMicros: 118_000),
      ),
    );
  }
  /// Creates a profile; fails closed via `ensureValid` in the factory
  /// constructors — use [validate] results through [ensure] when
  /// composing programmatically.
  const BehaviorProfile._(
    this.rhythm,
    this.reaction,
    this.pacing,
    this.pointer,
    this.cadence,
  );

  /// Deserializes a profile from its canonical JSON shape.
  factory BehaviorProfile.fromJson(Map<String, Object?> json) =>
      BehaviorProfile(
        rhythm: ActionRhythm.fromJson(json['rhythm']! as Map<String, Object?>),
        reaction: ReactionDelay.fromJson(
          json['reaction']! as Map<String, Object?>,
        ),
        pacing: SessionPacing.fromJson(json['pacing']! as Map<String, Object?>),
        pointer: PointerMotion.fromJson(
          json['pointer']! as Map<String, Object?>,
        ),
        cadence: KeystrokeCadence.fromJson(
          json['cadence']! as Map<String, Object?>,
        ),
      );

  /// The canonical degenerate profile: zero timing, direct paths — today's
  /// teleporting delivery, made explicit. Survives `synthesize` and
  /// `audit` untouched; that survival is the human/agent symmetry
  /// litmus test (ADR 0044).
  static final BehaviorProfile agentImmediate = BehaviorProfile();

  /// Decile boundaries (µs) for inter-key intervals, scaled per session.
  static List<int> _scaledDigraph(BehaviorRng rng) {
    const base = [
      34,
      52,
      68,
      84,
      102,
      124,
      152,
      192,
      258,
      368,
      540,
    ];
    final scale = rng.nextBetween(80, 125) / 100;
    return [
      for (final micros in base) (micros * 1000 * scale).round(),
    ];
  }

  /// Dwell before each dispatched action.
  final ActionRhythm rhythm;

  /// Observation→dispatch floor (driver-enforced).
  final ReactionDelay reaction;

  /// Session-level pacing.
  final SessionPacing pacing;

  /// Pointer delivery dynamics.
  final PointerMotion pointer;

  /// Keyboard delivery dynamics.
  final KeystrokeCadence cadence;

  /// Returns a copy with the given facets replaced.
  BehaviorProfile copyWith({
    ActionRhythm? rhythm,
    ReactionDelay? reaction,
    SessionPacing? pacing,
    PointerMotion? pointer,
    KeystrokeCadence? cadence,
  }) => BehaviorProfile(
    rhythm: rhythm ?? this.rhythm,
    reaction: reaction ?? this.reaction,
    pacing: pacing ?? this.pacing,
    pointer: pointer ?? this.pointer,
    cadence: cadence ?? this.cadence,
  );

  @override
  List<String> validate() => [
    ...rhythm.validate(),
    ...reaction.validate(),
    ...pacing.validate(),
    ...pointer.validate(),
    ...cadence.validate(),
  ];

  /// Validates and throws [SpecViolationException] with all violations.
  void ensure() => ensureValid();

  /// SHA-256 of the canonical JSON shape — the `profileHash` in receipts.
  String get hash => canonicalHash(toJson());

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'rhythm': rhythm.toJson(),
    'reaction': reaction.toJson(),
    'pacing': pacing.toJson(),
    'pointer': pointer.toJson(),
    'cadence': cadence.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is BehaviorProfile &&
      other.rhythm == rhythm &&
      other.reaction == reaction &&
      other.pacing == pacing &&
      other.pointer == pointer &&
      other.cadence == cadence;

  @override
  int get hashCode => Object.hash(rhythm, reaction, pacing, pointer, cadence);

  @override
  String toString() =>
      'BehaviorProfile($rhythm, $reaction, $pacing, $pointer, $cadence)';
}

/// Convenience re-export: the nominal target used by pre-flight
/// projection when no real element bounds exist yet.
const AxBounds nominalTarget = AxBounds(
  left: 0,
  top: 0,
  width: 120,
  height: 48,
);
