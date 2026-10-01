import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_driver.dart';
import 'cdp_page.dart';

/// The CDP lowering of the behavior contract (ADR 0044).
///
/// Dispatch semantics:
/// - **Stamp, not schedule.** CDP's `timestamp` parameter does not
///   schedule delivery; it only becomes the event's page-visible
///   `timeStamp`. The scheduler stamps every dispatch with its *planned*
///   time, so transport jitter is invisible to page-observable timing,
///   while actual pacing comes from the client-side wait.
/// - **Serialized awaited dispatches.** Each `Input.*` request completes
///   before the next is sent, so ordering down → moves → up is
///   guaranteed; unawaited pipelining lets renderer-side coalescing drop
///   or reorder fast moves.
/// - **Navigation gate.** A dispatch that spans a navigation truncates
///   loudly (`BehaviorVerdict.truncated`, cause `navigation`) instead of
///   firing into a stale surface.
///
/// v1 refusals (loud, per the family's refuse-not-degrade rule):
/// `SessionPacing.noiseEventRate > 0` and non-zero `driftPerHourUs` are
/// declared data the CDP lowering cannot honor yet — they throw
/// [DriverUnsupportedException] rather than silently flattening.
class BehavioralCdpDriver extends CdpDriver implements BehavioralDriver {
  /// Creates a behavioral driver over an attached [CdpPage].
  BehavioralCdpDriver(super.page);

  @override
  DriverCapabilities get capabilities => DriverCapabilities.full;

  (double, double) _pointer = (0, 0);

  /// The scheduler used for dispatches; overridable in tests.
  CdpBehaviorScheduler newScheduler() => CdpBehaviorScheduler(page: page);

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
    if (profile.pacing.noiseEventRate > 0) {
      throw const DriverUnsupportedException(
        'SessionPacing.noiseEventRate > 0 is not honored by the CDP '
        'lowering yet; keep it at 0 (refusing to silently flatten '
        'declared dynamics)',
      );
    }
    if (profile.pacing.driftPerHourUs != 0) {
      throw const DriverUnsupportedException(
        'SessionPacing.driftPerHourUs != 0 is not honored by the CDP '
        'lowering yet; keep it at 0 (refusing to silently flatten '
        'declared dynamics)',
      );
    }

    await _enforceReactionFloor(profile.reaction.floorUs);

    final bounds = await _resolveTarget(action);
    final effectiveSeed = seed ?? _freshSeed();
    final plan = synthesizeBehavior(
      profile,
      effectiveSeed,
      action,
      target: bounds,
      start: _pointer,
    );
    final outcome = await newScheduler().dispatch(plan);

    final moves = plan.steps.whereType<PointerMoveStep>().toList();
    if (moves.isNotEmpty) {
      _pointer = (moves.last.x, moves.last.y);
    } else if (bounds != null) {
      _pointer = bounds.center;
    }
    return outcome;
  }

  Future<void> _enforceReactionFloor(int floorUs) async {
    if (floorUs <= 0) return;
    final observedAt = page.lastObservationAt;
    if (observedAt == null) return;
    final elapsedUs = DateTime.now().difference(observedAt).inMicroseconds;
    final remainingUs = floorUs - elapsedUs;
    if (remainingUs > 0) {
      await Future<void>.delayed(Duration(microseconds: remainingUs));
    }
  }

  Future<AxBounds?> _resolveTarget(AutomationAction action) async {
    final String? css = switch (action) {
      ClickAction(:final css) => css,
      TypeAction(:final css) => css,
      _ => null,
    };
    if (css == null) return null;
    return page.resolveRect(css);
  }
}

/// Client-side scheduler materializing a plan onto one CDP page.
final class CdpBehaviorScheduler {
  /// Creates a scheduler over [page].
  CdpBehaviorScheduler({required this.page, this.timeout});

  /// The page to dispatch onto.
  final CdpPage page;

  /// Overall deadline for the whole dispatch; `null` means unbounded.
  final Duration? timeout;

  /// Dispatches [plan] and reports actual timing per step.
  Future<BehaviorOutcome> dispatch(BehaviorPlan plan) async {
    final revisionAtStart = page.revision;
    final watch = Stopwatch()..start();
    final wallStartMs = DateTime.now().millisecondsSinceEpoch;
    final deadlineUs = timeout?.inMicroseconds;
    final dispatched = <DispatchedStep>[];
    var verdict = BehaviorVerdict.complete;
    BehaviorInterruptionCause? cause;
    var pointerX = 0.0;
    var pointerY = 0.0;

    Future<Map<String, Object?>> send(
      String method,
      Map<String, Object?> params,
    ) => page.connection.send(method, params);

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      final interrupted = () {
        if (page.revision != revisionAtStart) {
          return BehaviorInterruptionCause.navigation;
        }
        final deadline = deadlineUs;
        if (deadline != null && watch.elapsedMicroseconds > deadline) {
          return BehaviorInterruptionCause.timeout;
        }
        return null;
      }();
      if (interrupted != null) {
        verdict = dispatched.isEmpty
            ? BehaviorVerdict.aborted
            : BehaviorVerdict.truncated;
        cause = interrupted;
        break;
      }
      final remainingUs = step.plannedAtUs - watch.elapsedMicroseconds;
      if (remainingUs > 0) {
        await Future<void>.delayed(Duration(microseconds: remainingUs));
      }
      // The surface may have navigated while waiting.
      if (page.revision != revisionAtStart) {
        verdict = dispatched.isEmpty
            ? BehaviorVerdict.aborted
            : BehaviorVerdict.truncated;
        cause = BehaviorInterruptionCause.navigation;
        break;
      }

      // The planned time becomes the event's page-visible timeStamp:
      // delivery jitter stays invisible to page-observable timing.
      final timestampSec = (wallStartMs + step.plannedAtUs / 1000) / 1000.0;
      switch (step) {
        case DwellStep():
          break;
        case PointerMoveStep(:final x, :final y):
          pointerX = x;
          pointerY = y;
          await send('Input.dispatchMouseEvent', {
            'type': 'mouseMoved',
            'x': x,
            'y': y,
            'timestamp': timestampSec,
          });
        case PointerDownStep(:final button):
          await send('Input.dispatchMouseEvent', {
            'type': 'mousePressed',
            'x': pointerX,
            'y': pointerY,
            'button': button,
            'clickCount': 1,
            'timestamp': timestampSec,
          });
        case PointerUpStep(:final button):
          await send('Input.dispatchMouseEvent', {
            'type': 'mouseReleased',
            'x': pointerX,
            'y': pointerY,
            'button': button,
            'clickCount': 1,
            'timestamp': timestampSec,
          });
        case KeyDownStep(:final key, :final keyCode, :final text):
          await send('Input.dispatchKeyEvent', {
            'type': 'keyDown',
            'key': key,
            'code': key,
            'windowsVirtualKeyCode': ?keyCode,
            'text': ?text,
            'unmodifiedText': ?text,
            'timestamp': timestampSec,
          });
        case KeyUpStep(:final key, :final keyCode):
          await send('Input.dispatchKeyEvent', {
            'type': 'keyUp',
            'key': key,
            'code': key,
            'windowsVirtualKeyCode': ?keyCode,
            'timestamp': timestampSec,
          });
        case CharStep(:final text):
          await send('Input.insertText', {'text': text});
        case WheelStep(:final deltaX, :final deltaY):
          await send('Input.dispatchMouseEvent', {
            'type': 'mouseWheel',
            'x': pointerX,
            'y': pointerY,
            'deltaX': deltaX,
            'deltaY': deltaY,
            'timestamp': timestampSec,
          });
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
}

/// Writes the behavior receipt pair for a dispatch, mirroring the
/// screencast recording contract: `<base>.behavior.stream.jsonl` — a meta
/// line plus one canonical step document per line — and
/// `<base>.behavior.receipts.jsonl` — an envelope, one line per dispatched
/// event, and a terminal line. A receipt records what was planned and
/// dispatched; it never claims what the page did.
final class CdpBehaviorReceiptWriter {
  /// Creates a writer emitting `<directory>/<base>.*` files.
  CdpBehaviorReceiptWriter({
    required String directory,
    String base = 'behavior',
  }) : _streamPath = '$directory/$base.behavior.stream.jsonl',
       _receiptsPath = '$directory/$base.behavior.receipts.jsonl';

  final String _streamPath;
  final String _receiptsPath;

  /// Path of the canonical plan artifact.
  String get streamPath => _streamPath;

  /// Path of the receipt manifest.
  String get receiptsPath => _receiptsPath;

  /// Writes both artifacts for one profiled dispatch.
  Future<void> write({
    required BehaviorProfile profile,
    required int seed,
    required String driverId,
    required String transport,
    required BehaviorOutcome outcome,
    String? sessionId,
  }) async {
    final streamBuffer = StringBuffer()
      ..writeln(
        canonicalJson({
          'schema': BehaviorPlan.schemaId,
          'profileHash': profile.hash,
          'seed': seed,
          'rng': BehaviorRng.algorithmId,
          'seeder': BehaviorRng.seederId,
        }),
      );
    for (final step in outcome.plan.steps) {
      streamBuffer.writeln(canonicalJson(step.toJson()));
    }
    final receiptsBuffer = StringBuffer()
      ..writeln(
        canonicalJson(
          BehaviorReceipts.envelope(
            profileHash: profile.hash,
            seed: seed,
            driverId: driverId,
            transport: transport,
            sessionId: sessionId,
          ),
        ),
      );
    for (final dispatched in outcome.dispatched) {
      receiptsBuffer.writeln(canonicalJson(dispatched.toJson()));
    }
    receiptsBuffer.writeln(
      canonicalJson(
        BehaviorReceipts.terminal(
          outcome: outcome,
          maxDriftUs: BehaviorReceipts.maxDriftUs(outcome.dispatched),
        ),
      ),
    );

    final streamFile = File(_streamPath);
    await streamFile.parent.create(recursive: true);
    await streamFile.writeAsString(streamBuffer.toString());
    final receiptsFile = File(_receiptsPath);
    await receiptsFile.parent.create(recursive: true);
    await receiptsFile.writeAsString(receiptsBuffer.toString());
  }
}
