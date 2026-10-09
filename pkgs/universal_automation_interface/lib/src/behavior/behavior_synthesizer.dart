import 'dart:math' as math;

import '../automation_action.dart';
import '../automation_exceptions.dart';
import '../keyboard_modifiers.dart';
import '../snapshot.dart';
import 'behavior_profile.dart';
import 'behavior_rng.dart';
import 'behavior_step.dart';

/// Deterministic plan synthesis (ADR 0044): same (profile, seed, action,
/// target, start) always yields the same plan, byte-for-byte, on every
/// platform.
///
/// A plan is *target-anchored materialization on demand*: plans are
/// concrete-coordinate, but coordinates come from the caller at
/// synthesis time — drivers re-synthesize with the live element bounds
/// (and their tracked pointer position) at dispatch, so a stale plan can
/// never fire into stale coordinates. Pre-flight projection uses
/// [nominalTarget].
///
/// The reaction floor ([ReactionDelay]) is deliberately **not** part of
/// the plan: it is the driver's job to enforce it against its last
/// observation timestamp, because only the driver knows when observation
/// happened.
BehaviorPlan synthesizeBehavior(
  BehaviorProfile profile,
  int seed,
  AutomationAction action, {
  AxBounds? target,
  (double, double) start = (0, 0),
}) {
  final rng = BehaviorRng(seed);
  final steps = <BehaviorStep>[];
  var cursorUs = 0;
  var pointer = start;

  void advance(int deltaUs) => cursorUs += deltaUs;

  void leadDwell() {
    final durationUs = profile.rhythm.beforeAction.sample(rng);
    if (durationUs > 0) {
      steps.add(DwellStep(plannedAtUs: cursorUs, durationUs: durationUs));
      advance(durationUs);
    }
  }

  // Teleporting delivery (zero-timing move distribution) synthesizes no
  // move steps at all — absence is the degenerate profile, not a
  // special-cased flag.
  final animatePointer = profile.pointer.moveDuration.meanUs > 0;

  // Chord lowering (ADR 0053): modifiers become key steps around the
  // gesture AND ride the pointer steps, so transports with a native
  // modifier field (CDP) set it while transports without (W3C, CGEvent
  // key events) still see the held keys.
  void chordDown(List<String> modifiers) {
    for (final modifier in modifiers) {
      final key = modifierKeyName(modifier);
      steps.add(
        KeyDownStep(
          plannedAtUs: cursorUs,
          key: key,
          keyCode: namedVirtualKeyCode(key),
        ),
      );
      advance(profile.cadence.digraph.sample(rng));
    }
  }

  void chordUp(List<String> modifiers) {
    for (final modifier in modifiers.reversed) {
      final key = modifierKeyName(modifier);
      steps.add(
        KeyUpStep(
          plannedAtUs: cursorUs,
          key: key,
          keyCode: namedVirtualKeyCode(key),
        ),
      );
      advance(profile.cadence.digraph.sample(rng));
    }
  }

  void moveTowards(double x, double y) {
    if (!animatePointer) {
      pointer = (x, y);
      return;
    }
    for (final segment in _pathSegments(profile, rng, pointer, (x, y))) {
      final (sx, sy) = segment.start;
      final (ex, ey) = segment.end;
      final durationUs = profile.pointer.moveDuration.sample(rng);
      final length = _distance(sx, sy, ex, ey);
      final stride = profile.pointer.maxStepPx.toDouble();
      final pointCount = math.max(2, (length / stride).ceil() + 1);
      final control = _controlPoint(profile.pointer.path, sx, sy, ex, ey);
      for (var i = 1; i <= pointCount; i++) {
        final eased = _easeOut(i / pointCount);
        // Quadratic de Casteljau: only + - * (correctly-rounded on every
        // platform), so eased positions are bit-stable.
        final ix = (1 - eased) * sx + eased * control.$1;
        final iy = (1 - eased) * sy + eased * control.$2;
        final fx = (1 - eased) * control.$1 + eased * ex;
        final fy = (1 - eased) * control.$2 + eased * ey;
        steps.add(
          PointerMoveStep(
            plannedAtUs: cursorUs,
            x: (1 - eased) * ix + eased * fx,
            y: (1 - eased) * iy + eased * fy,
            durationUs: durationUs,
          ),
        );
        advance(durationUs);
      }
      pointer = (ex, ey);
    }
  }

  switch (action) {
    case NavigateAction():
    case EvaluateAction():
      leadDwell();
    case ClickAction():
      final bounds = target ?? nominalTarget;
      final (cx, cy) = bounds.center;
      leadDwell();
      final before = steps.length;
      moveTowards(cx, cy);
      if (steps.length == before) {
        // Zero-animation delivery still commits the pointer position:
        // down/up carry no coordinates, transports dispatch where the
        // pointer was last placed.
        steps.add(
          PointerMoveStep(plannedAtUs: cursorUs, x: cx, y: cy, durationUs: 0),
        );
      }
      steps.add(PointerDownStep(plannedAtUs: cursorUs));
      advance(profile.pointer.buttonHold.sample(rng));
      steps.add(PointerUpStep(plannedAtUs: cursorUs));
    case ClickAtAction(
      :final x,
      :final y,
      :final button,
      :final clickCount,
      :final modifiers,
    ):
      // Coordinate verbs (ADR 0053) ride the same humanized delivery:
      // lead dwell, bezier move to the point, then clickCount presses.
      leadDwell();
      final before = steps.length;
      moveTowards(x, y);
      if (steps.length == before) {
        steps.add(
          PointerMoveStep(plannedAtUs: cursorUs, x: x, y: y, durationUs: 0),
        );
      }
      chordDown(modifiers);
      for (var press = 0; press < clickCount.clamp(1, 3); press++) {
        steps.add(
          PointerDownStep(
            plannedAtUs: cursorUs,
            button: button,
            clickCount: press + 1,
            modifiers: modifiers,
          ),
        );
        advance(profile.pointer.buttonHold.sample(rng));
        steps.add(
          PointerUpStep(
            plannedAtUs: cursorUs,
            button: button,
            clickCount: press + 1,
            modifiers: modifiers,
          ),
        );
        if (press + 1 < clickCount) {
          advance(profile.cadence.digraph.sample(rng));
        }
      }
      chordUp(modifiers);
    case MoveAction(:final x, :final y):
      leadDwell();
      final before = steps.length;
      moveTowards(x, y);
      if (steps.length == before) {
        steps.add(
          PointerMoveStep(plannedAtUs: cursorUs, x: x, y: y, durationUs: 0),
        );
      }
    case DragAction(
      :final fromX,
      :final fromY,
      :final toX,
      :final toY,
      :final button,
      :final modifiers,
    ):
      leadDwell();
      final before = steps.length;
      moveTowards(fromX, fromY);
      if (steps.length == before) {
        steps.add(
          PointerMoveStep(
            plannedAtUs: cursorUs,
            x: fromX,
            y: fromY,
            durationUs: 0,
          ),
        );
      }
      chordDown(modifiers);
      steps.add(
        PointerDownStep(
          plannedAtUs: cursorUs,
          button: button,
          modifiers: modifiers,
        ),
      );
      advance(profile.pointer.buttonHold.sample(rng));
      // The carried path humanizes too — a drag is a gesture, not a
      // teleport with the button held.
      moveTowards(toX, toY);
      steps.add(
        PointerUpStep(
          plannedAtUs: cursorUs,
          button: button,
          modifiers: modifiers,
        ),
      );
      chordUp(modifiers);
    case TypeAction(:final text, :final submit):
      leadDwell();
      for (final rune in text.runes) {
        final ch = String.fromCharCode(rune);
        if (rune >= 0x20 && rune <= 0x7e) {
          final keyCode = printableVirtualKeyCode(ch);
          steps.add(
            KeyDownStep(
              plannedAtUs: cursorUs,
              key: ch,
              keyCode: keyCode,
              text: ch,
            ),
          );
          advance(profile.cadence.hold.sample(rng));
          steps.add(
            KeyUpStep(plannedAtUs: cursorUs, key: ch, keyCode: keyCode),
          );
        } else {
          steps.add(CharStep(plannedAtUs: cursorUs, text: ch));
        }
        advance(profile.cadence.digraph.sample(rng));
      }
      if (submit) {
        steps.add(
          KeyDownStep(plannedAtUs: cursorUs, key: 'Enter', keyCode: 13),
        );
        advance(profile.cadence.hold.sample(rng));
        steps.add(KeyUpStep(plannedAtUs: cursorUs, key: 'Enter', keyCode: 13));
      }
    case KeyPressAction(:final key, :final modifiers):
      final keyCode = namedVirtualKeyCode(key);
      if (keyCode == null) {
        final message = 'KeyPressAction key "$key" has no synthesis '
            'code; extend namedVirtualKeyCode or use TypeAction';
        throw SpecViolationException([message]);
      }
      leadDwell();
      chordDown(modifiers);
      steps.add(KeyDownStep(plannedAtUs: cursorUs, key: key, keyCode: keyCode));
      advance(profile.cadence.hold.sample(rng));
      steps.add(KeyUpStep(plannedAtUs: cursorUs, key: key, keyCode: keyCode));
      chordUp(modifiers);
    case ScrollAction(:final direction, :final distance):
      leadDwell();
      final amount = distance ?? 300;
      final (deltaX, deltaY) = switch (direction.toLowerCase()) {
        'up' => (0.0, -amount),
        'down' => (0.0, amount),
        'left' => (-amount, 0.0),
        'right' => (amount, 0.0),
        final other => throw _badDirection(other),
      };
      steps.add(
        WheelStep(plannedAtUs: cursorUs, deltaX: deltaX, deltaY: deltaY),
      );
    case InvokeAction(:final name):
      throw SpecViolationException([
        'InvokeAction("$name") carries its own dispatch; behavioral '
        'synthesis does not apply to catalog actions',
      ]);
  }

  return BehaviorPlan(steps: steps);
}

/// Pre-flight projection: the plan plus its dispatch-time budget.
///
/// Agents use this to check cost/latency bounds **before** spending a
/// round trip on a doomed dispatch; bounds are checked statically.
BehaviorProjection projectBehavior(
  BehaviorProfile profile,
  int seed,
  AutomationAction action, {
  AxBounds? target,
  (double, double) start = (0, 0),
}) {
  final plan = synthesizeBehavior(
    profile,
    seed,
    action,
    target: target,
    start: start,
  );
  return BehaviorProjection(
    plan: plan,
    projectedDurationUs: plan.totalDurationUs + profile.reaction.floorUs,
  );
}

/// The result of [projectBehavior].
final class BehaviorProjection {
  /// Creates a projection.
  const BehaviorProjection({
    required this.plan,
    required this.projectedDurationUs,
  });

  /// The synthesized plan.
  final BehaviorPlan plan;

  /// Plan duration plus the reaction floor: the earliest completion the
  /// driver can promise under this profile.
  final int projectedDurationUs;

  @override
  String toString() =>
      'BehaviorProjection(${plan.steps.length} steps, '
      '$projectedDurationUs us)';
}

SpecViolationException _badDirection(String direction) {
  final message = 'ScrollAction direction "$direction" is not one of '
      'up, down, left, or right';
  return SpecViolationException([message]);
}

final class _Segment {
  const _Segment(this.start, this.end);
  final (double, double) start;
  final (double, double) end;
}

/// Path segments between [from] and [to]: the overshoot excursion first
/// (when the profile demands one), then the corrective return.
List<_Segment> _pathSegments(
  BehaviorProfile profile,
  BehaviorRng rng,
  (double, double) from,
  (double, double) to,
) {
  final path = profile.pointer.path;
  if (path is BezierPath && path.overshootPx > 0) {
    final (fx, fy) = from;
    final (tx, ty) = to;
    final length = _distance(fx, fy, tx, ty);
    if (length > 1) {
      final dx = (tx - fx) / length;
      final dy = (ty - fy) / length;
      final past = (tx + dx * path.overshootPx, ty + dy * path.overshootPx);
      return [_Segment(from, past), _Segment(past, to)];
    }
  }
  return [_Segment(from, to)];
}

/// The quadratic control point for [path] between two endpoints: the
/// midpoint offset perpendicular to the line by `curvature * length`.
/// `DirectPath` yields the midpoint (a straight line).
(double, double) _controlPoint(
  PathModel path,
  double sx,
  double sy,
  double ex,
  double ey,
) {
  final curvature = switch (path) {
    DirectPath() => 0.0,
    final BezierPath bezier => bezier.curvature,
  };
  final dx = ex - sx;
  final dy = ey - sy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1e-9 || curvature == 0) {
    return ((sx + ex) / 2, (sy + ey) / 2);
  }
  // Unit normal (perpendicular, pointing "right" of travel).
  final nx = dy / length;
  final ny = -dx / length;
  final offset = curvature * length;
  return ((sx + ex) / 2 + nx * offset, (sy + ey) / 2 + ny * offset);
}

/// Ease-out quad on the move parameter — arithmetic only, so the eased
/// positions are bit-stable across platforms.
double _easeOut(double t) => 1 - (1 - t) * (1 - t);

double _distance(double ax, double ay, double bx, double by) {
  final dx = bx - ax;
  final dy = by - ay;
  return math.sqrt(dx * dx + dy * dy);
}

/// Virtual key code for a printable ASCII character (uppercase letter,
/// digit, or punctuation), or `null` outside that set. Shared by the
/// behavior synthesis and by per-char key lowerings so both paths agree
/// on codes.
int? printableVirtualKeyCode(String char) {
  final code = char.codeUnitAt(0);
  if (code >= 0x41 && code <= 0x5a) return code; // A-Z
  if (code >= 0x61 && code <= 0x7a) return code - 32; // a-z -> A-Z codes
  if (code >= 0x30 && code <= 0x39) return code; // 0-9
  return _punctuation[char];
}

const _punctuation = <String, int>{
  ' ': 32,
  '!': 49,
  '@': 50,
  '#': 51,
  r'$': 52,
  '%': 53,
  '^': 54,
  '&': 55,
  '*': 56,
  '(': 57,
  ')': 48,
  ';': 186,
  ':': 186,
  '=': 187,
  '+': 187,
  ',': 188,
  '<': 188,
  '-': 189,
  '_': 189,
  '.': 190,
  '>': 190,
  '/': 191,
  '?': 191,
  '`': 192,
  '~': 192,
  '[': 219,
  '{': 219,
  r'\': 220,
  '|': 220,
  ']': 221,
  '}': 221,
  "'": 222,
  '"': 222,
};

/// Virtual key code for the family's named-key set (`Enter`, `Tab`,
/// `Escape`, `Backspace`, arrows, and the modifier names), or `null`
/// outside it. Modifier codes follow the Windows VK conventions the
/// web tiers use; OS tiers re-map onto their native codes.
int? namedVirtualKeyCode(String key) => switch (key) {
  'Enter' => 13,
  'Tab' => 9,
  'Escape' => 27,
  'Backspace' => 8,
  'ArrowLeft' => 37,
  'ArrowUp' => 38,
  'ArrowRight' => 39,
  'ArrowDown' => 40,
  'Shift' => 16,
  'Control' => 17,
  'Alt' => 18,
  'Meta' => 91,
  _ => null,
};
