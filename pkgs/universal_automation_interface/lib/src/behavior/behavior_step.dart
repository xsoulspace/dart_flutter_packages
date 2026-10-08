import 'package:meta/meta.dart';

import '../automation_exceptions.dart';
import 'canonical.dart'
    show canonicalHash, canonicalJson, gridValue, pixelsFromGrid;

/// The timed input-step vocabulary: the one primitive language every
/// behavior plan is written in, every transport lowers, and every audit
/// consumes (ADR 0044).
///
/// Steps are payload-light and timed in integer microseconds relative to
/// the plan start (`plannedAtUs`). Coordinates are logical pixels;
/// canonical (hashing) form quantizes them to a hundredth-of-a-pixel
/// integer grid so no platform float formatting can reach a hash.
sealed class BehaviorStep {
  /// Creates a step planned at [plannedAtUs] microseconds.
  const BehaviorStep({required this.plannedAtUs});

  /// Deserializes a step from its canonical JSON shape.
  factory BehaviorStep.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'dwell' => DwellStep(
          plannedAtUs: json['plannedAtUs']! as int,
          durationUs: json['durationUs']! as int,
        ),
        'pointerMove' => PointerMoveStep(
          plannedAtUs: json['plannedAtUs']! as int,
          x: pixelsFromGrid(json['x']! as int),
          y: pixelsFromGrid(json['y']! as int),
          durationUs: json['durationUs']! as int,
        ),
        'pointerDown' => PointerDownStep(
          plannedAtUs: json['plannedAtUs']! as int,
          button: json['button']! as String? ?? 'left',
        ),
        'pointerUp' => PointerUpStep(
          plannedAtUs: json['plannedAtUs']! as int,
          button: json['button']! as String? ?? 'left',
        ),
        'keyDown' => KeyDownStep(
          plannedAtUs: json['plannedAtUs']! as int,
          key: json['key']! as String,
          keyCode: json['keyCode'] as int?,
          text: json['text'] as String?,
        ),
        'keyUp' => KeyUpStep(
          plannedAtUs: json['plannedAtUs']! as int,
          key: json['key']! as String,
          keyCode: json['keyCode'] as int?,
        ),
        'char' => CharStep(
          plannedAtUs: json['plannedAtUs']! as int,
          text: json['text']! as String,
        ),
        'wheel' => WheelStep(
          plannedAtUs: json['plannedAtUs']! as int,
          deltaX: pixelsFromGrid(json['deltaX']! as int),
          deltaY: pixelsFromGrid(json['deltaY']! as int),
        ),
        final other => throw FormatException('unknown BehaviorStep "$other"'),
      };

  /// Microseconds from the plan start to this step.
  final int plannedAtUs;

  /// Stable kind tag; the canonical discriminator.
  String get kind;

  /// Canonical JSON shape; kind-tagged.
  Map<String, Object?> toJson();
}

/// An explicit pause. Gaps in `plannedAtUs` and explicit dwells carry the
/// same semantics; explicit dwells make plans self-describing for audits.
@immutable
final class DwellStep extends BehaviorStep {
  /// Creates a pause of [durationUs] starting at [plannedAtUs].
  const DwellStep({required super.plannedAtUs, required this.durationUs});

  /// How long the pause lasts, in microseconds.
  final int durationUs;

  @override
  String get kind => 'dwell';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'durationUs': durationUs,
  };

  @override
  String toString() => 'DwellStep(+$plannedAtUs us, $durationUs us)';
}

/// Move the pointer to logical-pixel ([x], [y]) over [durationUs].
@immutable
final class PointerMoveStep extends BehaviorStep {
  /// Creates a move step.
  const PointerMoveStep({
    required super.plannedAtUs,
    required this.x,
    required this.y,
    required this.durationUs,
  });

  /// Destination x, logical pixels.
  final double x;

  /// Destination y, logical pixels.
  final double y;

  /// Move duration, in microseconds.
  final int durationUs;

  @override
  String get kind => 'pointerMove';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'x': gridValue(x),
    'y': gridValue(y),
    'durationUs': durationUs,
  };

  @override
  String toString() =>
      'PointerMoveStep(+$plannedAtUs us -> (${x.toStringAsFixed(1)}, '
      '${y.toStringAsFixed(1)}) over $durationUs us)';
}

/// Press a pointer [button] (`left` by default).
@immutable
final class PointerDownStep extends BehaviorStep {
  /// Creates a press step.
  const PointerDownStep({
    required super.plannedAtUs,
    this.button = 'left',
    this.clickCount = 1,
  });

  /// Button name: `left`, `right`, or `middle`.
  final String button;

  /// Which press of a multi-click sequence this is (1 = single,
  /// 2 = the second press of a double-click — the transport's
  /// `clickCount`, ADR 0053).
  final int clickCount;

  @override
  String get kind => 'pointerDown';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'button': button,
    'clickCount': clickCount,
  };

  @override
  String toString() => 'PointerDownStep(+$plannedAtUs us, $button)';
}

/// Release a pointer [button].
@immutable
final class PointerUpStep extends BehaviorStep {
  /// Creates a release step.
  const PointerUpStep({
    required super.plannedAtUs,
    this.button = 'left',
    this.clickCount = 1,
  });

  /// Button name: `left`, `right`, or `middle`.
  final String button;

  /// Which release of a multi-click sequence this is (pairs with
  /// [PointerDownStep.clickCount]).
  final int clickCount;

  @override
  String get kind => 'pointerUp';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'button': button,
    'clickCount': clickCount,
  };

  @override
  String toString() => 'PointerUpStep(+$plannedAtUs us, $button)';
}

/// Press a key: named [key], optional platform [keyCode] and printable
/// [text] payload.
@immutable
final class KeyDownStep extends BehaviorStep {
  /// Creates a key-down step.
  const KeyDownStep({
    required super.plannedAtUs,
    required this.key,
    this.keyCode,
    this.text,
  });

  /// Logical key name (e.g. `Enter`, `a`).
  final String key;

  /// Platform virtual key code, when known.
  final int? keyCode;

  /// Printable text the key produces, when any.
  final String? text;

  @override
  String get kind => 'keyDown';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'key': key,
    'keyCode': keyCode,
    'text': text,
  };

  @override
  String toString() => 'KeyDownStep(+$plannedAtUs us, $key)';
}

/// Release a key: named [key], optional platform [keyCode].
@immutable
final class KeyUpStep extends BehaviorStep {
  /// Creates a key-up step.
  const KeyUpStep({
    required super.plannedAtUs,
    required this.key,
    this.keyCode,
  });

  /// Logical key name (e.g. `Enter`, `a`).
  final String key;

  /// Platform virtual key code, when known.
  final int? keyCode;

  @override
  String get kind => 'keyUp';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'key': key,
    'keyCode': keyCode,
  };

  @override
  String toString() => 'KeyUpStep(+$plannedAtUs us, $key)';
}

/// Deliver printable [text] as a character event (the lowering may choose
/// IME-style insertion, e.g. CDP `Input.insertText`, for non-ASCII runes).
@immutable
final class CharStep extends BehaviorStep {
  /// Creates a character step.
  const CharStep({required super.plannedAtUs, required this.text});

  /// The text delivered by this event.
  final String text;

  @override
  String get kind => 'char';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'text': text,
  };

  @override
  String toString() => 'CharStep(+$plannedAtUs us, "${text.length} chars")';
}

/// Wheel/scroll deltas at the current pointer position.
@immutable
final class WheelStep extends BehaviorStep {
  /// Creates a wheel step.
  const WheelStep({
    required super.plannedAtUs,
    required this.deltaX,
    required this.deltaY,
  });

  /// Horizontal delta, logical pixels (positive scrolls right).
  final double deltaX;

  /// Vertical delta, logical pixels (positive scrolls down).
  final double deltaY;

  @override
  String get kind => 'wheel';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'plannedAtUs': plannedAtUs,
    'deltaX': gridValue(deltaX),
    'deltaY': gridValue(deltaY),
  };

  @override
  String toString() =>
      'WheelStep(+$plannedAtUs us, d=($deltaX, $deltaY))';
}

/// The deterministic canonical plan `synthesize` produces: steps in
/// `plannedAtUs` order, hashable, serializable, replayable byte-for-byte.
///
/// A plan is a *plan*, not a schedule to fire blind (ADR 0044): segments
/// are re-resolved against the live surface at dispatch, and interruption
/// semantics belong to the driver's `BehaviorOutcome`, never to the plan.
final class BehaviorPlan {
  /// Creates a plan; steps are sorted by `plannedAtUs` and validated to
  /// be non-negative.
  BehaviorPlan({required List<BehaviorStep> steps})
    : steps = List.of(steps)..sort(
        (a, b) => a.plannedAtUs.compareTo(b.plannedAtUs),
      ) {
    for (final step in steps) {
      if (step.plannedAtUs < 0) {
        throw SpecViolationException([
          'BehaviorStep.plannedAtUs must be >= 0 (got ${step.plannedAtUs})',
        ]);
      }
    }
  }

  /// Deserializes a plan from its canonical JSON shape.
  factory BehaviorPlan.fromJson(Map<String, Object?> json) {
    if (json['schema'] != schemaId) {
      throw FormatException(
        'expected ${schemaId.replaceAll('/', '.')}, got ${json['schema']}',
      );
    }
    return BehaviorPlan(
      steps: (json['steps']! as List<Object?>)
          .whereType<Map<String, Object?>>()
          .map(BehaviorStep.fromJson)
          .toList(),
    );
  }

  /// Wire/format identifier pinned into hashes and receipts.
  static const String schemaId = 'behavior.plan/v1';

  /// The ordered steps.
  final List<BehaviorStep> steps;

  /// Total planned duration in microseconds (0 for an empty plan).
  int get totalDurationUs {
    if (steps.isEmpty) return 0;
    final last = steps.last;
    final end = switch (last) {
      DwellStep(:final durationUs) => last.plannedAtUs + durationUs,
      PointerMoveStep(:final durationUs) => last.plannedAtUs + durationUs,
      _ => last.plannedAtUs,
    };
    return end;
  }

  /// One canonical JSON document per line, in plan order.
  String canonicalJsonl() => [
    for (final step in steps) canonicalJson(step.toJson()),
  ].join('\n');

  /// SHA-256 of [canonicalJsonl] — the `streamHash` in receipts.
  String get hash => canonicalHash(steps.map((s) => s.toJson()).toList());

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'schema': schemaId,
    'steps': [for (final step in steps) step.toJson()],
  };

  @override
  String toString() => 'BehaviorPlan(${steps.length} steps, '
      '$totalDurationUs us, ${hash.substring(0, 8)})';
}
