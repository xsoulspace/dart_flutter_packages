import 'dart:async';

import 'automation_exceptions.dart';
import 'snapshot.dart';

/// An exact semantic locator. Scopes are resolved uniquely, outermost first.
/// A target is re-resolved on each operation; it is not a retained element ref.
class SemanticTarget {
  /// Creates an exact target with optional ordered ancestor scopes.
  const SemanticTarget({this.role, this.name, this.scope = const []})
    : assert(role != null || name != null, 'A role or name is required');

  /// Exact semantic role, when constrained.
  final String? role;

  /// Exact accessible name, when constrained.
  final String? name;

  /// Ordered ancestor scopes; each must resolve to one node.
  final List<SemanticTarget> scope;

  /// Tests the role/name without applying ancestor scopes.
  bool matches(AxNode node) =>
      (role == null || node.role == role) &&
      (name == null || node.name == name);

  /// Serializes the locator for diagnostics.
  Map<String, Object?> toJson() => {
    if (role != null) 'role': role,
    if (name != null) 'name': name,
    if (scope.isNotEmpty) 'scope': scope.map((s) => s.toJson()).toList(),
  };
}

/// No target or more than one target is a refusal, not an ordering rule.
class TargetResolutionException extends AutomationException {
  /// Records the failing locator and number of candidates.
  TargetResolutionException(SemanticTarget target, int count)
    : super(
        'semantic target matched $count nodes',
        details: {'target': target.toJson(), 'count': count},
      );
  @override
  String get kind => 'targetResolution';
}

/// Resolves one node in a fresh snapshot, preserving its adapter attributes.
AxNode resolveSemanticTarget(Snapshot snapshot, SemanticTarget target) {
  Iterable<AxNode> candidates = snapshot.nodes;
  AxNode unique(SemanticTarget locator, Iterable<AxNode> nodes) {
    if (locator.role == null && locator.name == null) {
      throw ArgumentError('A semantic target requires a role or name');
    }
    final matches = nodes.where(locator.matches).toList();
    if (matches.length != 1) {
      throw TargetResolutionException(locator, matches.length);
    }
    return matches.single;
  }

  for (final scope in target.scope) {
    if (scope.scope.isNotEmpty) {
      throw ArgumentError('Scope entries must not contain nested scopes');
    }
    final parent = unique(scope, candidates);
    candidates = parent.children.expand((child) => child.walk());
  }
  return unique(target, candidates);
}

/// Optional capability; it does not add variants to the sealed action set.
abstract interface class TargetedAutomationDriver {
  /// Resolves one current target and dispatches one pointer click.
  Future<void> clickTarget(SemanticTarget target);

  /// Focuses the element and verifies element focus. This is not OS focus.
  Future<void> focusTarget(SemanticTarget target);
}

/// Evidence about the one dispatch attempt.
enum EffectDelivery {
  /// Existing state satisfied the postcondition, so no action ran.
  notDispatched,

  /// The dispatch Future completed.
  completed,

  /// Dispatch failed or expired; the application may still have changed.
  unknown,
}

/// Independent application postcondition evidence.
enum EffectObservation {
  /// The baseline already satisfied the declared postcondition.
  alreadySatisfied,

  /// A later observation satisfied the declared postcondition.
  observed,

  /// The deadline elapsed without the required observation.
  timedOut,
}

/// Transport completion and application effect are independent observations.
class EffectReceipt<T> {
  /// Creates the evidence receipt.
  const EffectReceipt({
    required this.before,
    required this.after,
    required this.delivery,
    required this.effect,
    required this.observations,
    this.dispatchError,
    this.observationError,
  });

  /// Baseline observed before dispatch.
  final T before;

  /// Last successfully observed value.
  final T after;

  /// Whether dispatch completed, failed/expired, or was skipped.
  final EffectDelivery delivery;

  /// Independent postcondition evidence.
  final EffectObservation effect;

  /// Number of successful observations including the baseline.
  final int observations;

  /// Delivery error or timeout; does not imply the effect failed.
  final String? dispatchError;

  /// Last unsuccessful observation diagnostic.
  final String? observationError;

  /// True only when the postcondition was observed.
  bool get verified => effect != EffectObservation.timedOut;
}

/// Dispatches at most once, then observes with one monotonic deadline.
/// A delivery timeout/error never causes replay. Later effect observation may
/// still succeed. Futures must tolerate their completion after a timeout.
/// Initial observation failure propagates: without a baseline no action runs.
Future<EffectReceipt<T>> verifyEffect<T>({
  required Future<void> Function() dispatch,
  required Future<T> Function() observe,
  required bool Function(T before, T after) changed,
  bool Function(T value)? isSatisfied,
  Duration timeout = const Duration(seconds: 5),
  Duration dispatchTimeout = const Duration(seconds: 1),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  if (timeout <= Duration.zero ||
      dispatchTimeout <= Duration.zero ||
      pollInterval <= Duration.zero) {
    throw ArgumentError('Verification durations must be positive');
  }
  final clock = Stopwatch()..start();
  Duration remaining() => timeout - clock.elapsed;
  final before = await observe().timeout(remaining());
  var after = before;
  if (isSatisfied?.call(before) ?? false) {
    return EffectReceipt(
      before: before,
      after: after,
      delivery: EffectDelivery.notDispatched,
      effect: EffectObservation.alreadySatisfied,
      observations: 1,
    );
  }
  var delivery = EffectDelivery.completed;
  String? dispatchError;
  String? observationError;
  var observations = 1;
  try {
    final budget = remaining();
    if (budget <= Duration.zero) {
      throw TimeoutException('Baseline used deadline');
    }
    await dispatch().timeout(
      budget < dispatchTimeout ? budget : dispatchTimeout,
    );
  } on Object catch (error) {
    delivery = EffectDelivery.unknown;
    dispatchError = error.toString();
  }
  while (remaining() > Duration.zero) {
    try {
      after = await observe().timeout(remaining());
      observations++;
      if (isSatisfied == null ? changed(before, after) : isSatisfied(after)) {
        return EffectReceipt(
          before: before,
          after: after,
          delivery: delivery,
          effect: EffectObservation.observed,
          observations: observations,
          dispatchError: dispatchError,
          observationError: observationError,
        );
      }
    } on Object catch (error) {
      observationError = error.toString();
    }
    final budget = remaining();
    if (budget <= Duration.zero) break;
    await Future<void>.delayed(budget < pollInterval ? budget : pollInterval);
  }
  return EffectReceipt(
    before: before,
    after: after,
    delivery: delivery,
    effect: EffectObservation.timedOut,
    observations: observations,
    dispatchError: dispatchError,
    observationError: observationError,
  );
}
