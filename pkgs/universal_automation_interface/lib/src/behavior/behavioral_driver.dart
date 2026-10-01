import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../automation_action.dart';
import '../driver.dart';
import '../driver_capabilities.dart';
import '../snapshot.dart';
import 'behavior_profile.dart';
import 'behavior_step.dart';

/// Drivers that can deliver actions under a declared behavior profile.
///
/// Opt-in capability surface: plain `AutomationDriver`s stay untouched and
/// drivers without the machinery keep `behaviorDynamics: false` and refuse
/// loudly. Facets the transport cannot honor throw
/// `DriverUnsupportedException` — never silently degrade (ADR 0044).
abstract interface class BehavioralDriver implements AutomationDriver {
  /// Performs [action], delivering input according to [profile].
  ///
  /// The driver materializes the plan against the live surface at
  /// dispatch (target re-resolution), enforces the reaction floor against
  /// its last observation, and reports what actually happened in the
  /// outcome — planned/dispatched times, drift, and a terminal verdict.
  ///
  /// [seed] makes synthesis deterministic (tests, CI, golden files);
  /// `null` draws fresh per-dispatch entropy, which is the production
  /// posture. Seeds for real sessions are sensitive: never reuse or log
  /// them.
  Future<BehaviorOutcome> performWith(
    AutomationAction action,
    BehaviorProfile profile, {
    int? seed,
  });
}

/// Terminal state of a profiled dispatch.
enum BehaviorVerdict {
  /// Every planned step was dispatched.
  complete,

  /// The dispatch stopped partway; the remaining steps were not sent.
  truncated,

  /// The dispatch was stopped before it could meaningfully start, or the
  /// surface invalidated it (e.g. navigation) with no committed prefix.
  aborted,
}

/// Why a dispatch did not complete.
enum BehaviorInterruptionCause {
  /// The surface navigated mid-dispatch.
  navigation,

  /// The driver's own deadline elapsed.
  timeout,

  /// The anchor element disappeared or moved beyond tolerance.
  targetLost,

  /// The caller requested cancellation.
  explicitCancel,

  /// The transport or connection died mid-dispatch.
  connectionLost,
}

/// One dispatched step with its actual timing.
@immutable
final class DispatchedStep {
  /// Creates a dispatched-step record.
  const DispatchedStep({
    required this.sequence,
    required this.step,
    required this.dispatchedAtUs,
    required this.driftUs,
  });

  /// Position in the plan (0-based).
  final int sequence;

  /// The step that was dispatched.
  final BehaviorStep step;

  /// Actual dispatch time relative to dispatch start, microseconds.
  final int dispatchedAtUs;

  /// `dispatchedAtUs - plannedAtUs`; positive means late.
  final int driftUs;

  /// Canonical JSON shape (receipt event line body).
  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'kind': step.kind,
    'plannedAtUs': step.plannedAtUs,
    'dispatchedAtUs': dispatchedAtUs,
    'driftUs': driftUs,
  };

  @override
  String toString() => 'DispatchedStep(#$sequence ${step.kind}, '
      'drift ${driftUs}us)';
}

/// The typed result of a profiled dispatch: what was planned, what
/// actually went out, and how the story ended.
///
/// No magic rollback: half-delivered input (a pressed button, half-typed
/// text) stays on the surface and is *reported*; the next snapshot shows
/// real state and the caller replans (ADR 0044).
@immutable
final class BehaviorOutcome {
  /// Creates an outcome.
  const BehaviorOutcome({
    required this.verdict,
    required this.plan,
    required this.dispatched,
    this.cause,
  });

  /// The full plan that was materialized for this dispatch.
  final BehaviorPlan plan;

  /// Terminal verdict.
  final BehaviorVerdict verdict;

  /// Why the dispatch ended early; `null` when [BehaviorVerdict.complete].
  final BehaviorInterruptionCause? cause;

  /// Dispatched steps in plan order, with actual timing and drift.
  final List<DispatchedStep> dispatched;

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'verdict': verdict.name,
    if (cause != null) 'cause': cause!.name,
    'plannedSteps': plan.steps.length,
    'dispatchedSteps': dispatched.length,
    'dispatched': [for (final step in dispatched) step.toJson()],
  };

  @override
  String toString() => 'BehaviorOutcome(${verdict.name}'
      '${cause == null ? '' : ', ${cause!.name}'}, '
      '${dispatched.length}/${plan.steps.length} dispatched)';
}

/// A `BehavioralDriver` wrapper holding an immutable default profile.
///
/// Profiles are data the caller selects per session; the wrapper exists
/// so a chosen default can ride along a driver reference without hidden
/// mutable state — `withProfile` returns a new wrapper, never mutates.
final class ProfiledDriver implements BehavioralDriver {
  /// Creates a wrapper dispatching every action under [defaultProfile].
  ProfiledDriver(this._inner, {BehaviorProfile? defaultProfile})
    : _defaultProfile = defaultProfile ?? BehaviorProfile.agentImmediate;

  final BehavioralDriver _inner;
  final BehaviorProfile _defaultProfile;

  @override
  DriverCapabilities get capabilities => _inner.capabilities;

  /// The profile this wrapper dispatches by default.
  BehaviorProfile get defaultProfile => _defaultProfile;

  /// A new wrapper over the same driver with [profile] as the default.
  ProfiledDriver withProfile(BehaviorProfile profile) =>
      ProfiledDriver(_inner, defaultProfile: profile);

  @override
  Future<Snapshot> snapshot() => _inner.snapshot();

  @override
  Future<void> perform(AutomationAction action) => _inner.perform(action);

  @override
  Future<Uint8List> screenshot() => _inner.screenshot();

  @override
  Future<void> close() => _inner.close();

  @override
  Future<BehaviorOutcome> performWith(
    AutomationAction action,
    BehaviorProfile profile, {
    int? seed,
  }) =>
      _inner.performWith(action, profile, seed: seed);

  /// Performs [action] under this wrapper's default profile.
  Future<BehaviorOutcome> performProfiled(
    AutomationAction action, {
    int? seed,
  }) =>
      performWith(action, _defaultProfile, seed: seed);
}
