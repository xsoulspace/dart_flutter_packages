import 'dart:math' as math;

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'driver_bridge.dart';
import 'macos_driver.dart';

/// The macOS lowering of the behavior contract (ADR 0044): the same
/// humanized plans the CDP tier dispatches over `Input.*` land here as
/// CGEvents through the native bridge — including the ADR 0053
/// coordinate verbs, so a profiled drag is a bezier gesture on the host,
/// not a teleport with the button held.
///
/// Dispatch semantics mirror [the CDP lowering]:
/// - **Client-side pacing.** The scheduler waits out each step's planned
///   offset on the wall clock; CGEvent posting has no schedule parameter.
/// - **Serialized dispatches.** Each bridge call completes before the
///   next; the OS event stream keeps global ordering.
/// - **No navigation gate.** AX offers no mid-dispatch surface-revision
///   signal, so a dispatch that the surface invalidated is reported by
///   the *next* observation, not truncated here (the CDP tier's gate has
///   no equivalent — stated in the ADR 0052/0053 non-claims).
///
/// Truncated dispatches can leave a button logically down in the bridge;
/// `releaseAll` (session teardown, driver close) posts the matching up
/// events so the host never keeps a stuck button.
final class BehavioralMacosDriver extends MacosDriver
    implements BehavioralDriver {
  /// Creates a behavioral driver over the native (or injected) bridge.
  BehavioralMacosDriver({
    super.bridge,
    super.snapshotDepth,
    super.snapshotMaxNodes,
  });

  (double, double) _pointer = (0, 0);

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
    pointerCoordinates: true,
    behaviorDynamics: true,
  );

  /// The scheduler used for dispatches; overridable in tests.
  MacosBehaviorScheduler newScheduler() => MacosBehaviorScheduler(bridge);

  int _freshSeed() {
    final secure = math.Random.secure();
    return (secure.nextInt(1 << 32) << 32) ^ secure.nextInt(1 << 32);
  }

  @override
  Future<BehaviorOutcome> performWith(
    AutomationAction action,
    BehaviorProfile profile, {
    int? seed,
  }) async {
    final floorUs = profile.reaction.floorUs;
    if (floorUs > 0) {
      final observedAt = lastObservationAt;
      if (observedAt != null) {
        final elapsedUs = DateTime.now()
            .difference(observedAt)
            .inMicroseconds;
        final remainingUs = floorUs - elapsedUs;
        if (remainingUs > 0) {
          await Future<void>.delayed(Duration(microseconds: remainingUs));
        }
      }
    }

    final plan = synthesizeBehavior(
      profile,
      seed ?? _freshSeed(),
      action,
      start: _pointer,
    );
    final outcome = await newScheduler().dispatch(plan);

    final moves = plan.steps.whereType<PointerMoveStep>().toList();
    if (moves.isNotEmpty) {
      _pointer = (moves.last.x, moves.last.y);
    }
    return outcome;
  }
}

/// Client-side scheduler materializing a behavior plan onto the native
/// bridge. `KeyDown`/`KeyUp` map through the bridge's named-key table
/// (code 1 = unmapped name, refused loudly mid-dispatch); `WheelStep`
/// pixels convert at the family's ~10 px per wheel line.
final class MacosBehaviorScheduler {
  /// Creates a scheduler over [bridge].
  MacosBehaviorScheduler(this.bridge, {this.timeout});

  /// The bridge every step dispatches through.
  final AxDriverBridge bridge;

  /// Overall deadline for the whole dispatch; `null` means unbounded.
  final Duration? timeout;

  /// Dispatches [plan] and reports actual timing per step.
  Future<BehaviorOutcome> dispatch(BehaviorPlan plan) async {
    final watch = Stopwatch()..start();
    final deadlineUs = timeout?.inMicroseconds;
    final dispatched = <DispatchedStep>[];
    var verdict = BehaviorVerdict.complete;
    BehaviorInterruptionCause? cause;
    var pointerX = 0.0;
    var pointerY = 0.0;

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      final deadline = deadlineUs;
      if (deadline != null && watch.elapsedMicroseconds > deadline) {
        verdict = dispatched.isEmpty
            ? BehaviorVerdict.aborted
            : BehaviorVerdict.truncated;
        cause = BehaviorInterruptionCause.timeout;
        break;
      }
      final remainingUs = step.plannedAtUs - watch.elapsedMicroseconds;
      if (remainingUs > 0) {
        await Future<void>.delayed(Duration(microseconds: remainingUs));
      }

      switch (step) {
        case DwellStep():
          break;
        case PointerMoveStep(:final x, :final y):
          _check(bridge.pointerMove(x: x, y: y), 'move pointer');
          pointerX = x;
          pointerY = y;
        case PointerDownStep(
          :final button,
          :final clickCount,
          :final modifiers,
        ):
          _check(
            bridge.pointerButton(
              x: pointerX,
              y: pointerY,
              button: button,
              down: true,
              clickCount: clickCount,
              modifiers: modifiers,
            ),
            'press $button',
          );
        case PointerUpStep(
          :final button,
          :final clickCount,
          :final modifiers,
        ):
          _check(
            bridge.pointerButton(
              x: pointerX,
              y: pointerY,
              button: button,
              down: false,
              clickCount: clickCount,
              modifiers: modifiers,
            ),
            'release $button',
          );
        case KeyDownStep(:final key):
          _checkNamed(bridge.keyDown(key), 'press key $key');
        case KeyUpStep(:final key):
          _checkNamed(bridge.keyUp(key), 'release key $key');
        case CharStep(:final text):
          _check(bridge.typeText(text), 'insert text');
        case WheelStep(:final deltaX, :final deltaY):
          // CDP-convention pixels (negative = up) flip into macOS wheel
          // lines (positive = up) at the family's ~10 px/line rate.
          _check(
            bridge.scroll(-deltaX / 10, -deltaY / 10),
            'scroll wheel',
          );
      }
      final atUs = watch.elapsedMicroseconds;
      dispatched.add(
        DispatchedStep(
          sequence: i,
          step: step,
          dispatchedAtUs: atUs,
          driftUs: atUs - step.plannedAtUs,
        ),
      );
    }
    return BehaviorOutcome(
      verdict: verdict,
      plan: plan,
      dispatched: dispatched,
      cause: cause,
    );
  }

  /// 0 ok · 10 permission missing · anything else is a protocol failure.
  void _check(int code, String operation) {
    if (code == 0) return;
    if (code == 10) {
      throw const AccessibilityPermissionRequiredException();
    }
    throw ProtocolException('$operation failed', code: code);
  }

  /// The named-key table's `1` (unknown key name) is a spec-level
  /// refusal, not a transport failure.
  void _checkNamed(int code, String operation) {
    if (code == 0) return;
    if (code == 1) {
      throw DriverUnsupportedException(
        '$operation: the key is not mapped by the macOS driver',
      );
    }
    _check(code, operation);
  }
}
