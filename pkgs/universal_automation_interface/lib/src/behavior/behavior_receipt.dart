import 'behavior_rng.dart';
import 'behavioral_driver.dart';

/// Receipt line encoders for behavior dispatches (ADR 0044).
///
/// Two JSONL artifacts per session mirror the screencast recording
/// contract (`recording`, `receipts`): `<base>.behavior.stream.jsonl` —
/// the canonical plan, one step document per line — and
/// `<base>.behavior.receipts.jsonl` — one envelope, one line per
/// dispatched event, and a terminal line. A receipt records what was
/// planned and dispatched; it never claims what the page did
/// (`receipt != evidence of effect`, but a receipt makes the dispatch
/// checkable).
// ignore: avoid_classes_with_only_static_members
abstract final class BehaviorReceipts {
  /// Schema identifier of the receipts artifact.
  static const String schemaId = 'behavior.receipts/v1';

  /// The session envelope line (first line of the receipts file).
  static Map<String, Object?> envelope({
    required String profileHash,
    required int seed,
    required String driverId,
    required String transport,
    String? sessionId,
  }) => {
    'schema': schemaId,
    'profileHash': profileHash,
    'seed': seed,
    'rng': BehaviorRng.algorithmId,
    'facetVersions': facetVersions,
    'driverId': driverId,
    'transport': transport,
    'sessionId': ?sessionId,
  };

  /// The terminal line (last line of the receipts file).
  static Map<String, Object?> terminal({
    required BehaviorOutcome outcome,
    required int maxDriftUs,
  }) => {
    'terminal': true,
    'verdict': outcome.verdict.name,
    if (outcome.cause != null) 'cause': outcome.cause!.name,
    'plannedSteps': outcome.plan.steps.length,
    'dispatchedSteps': outcome.dispatched.length,
    'maxDriftUs': maxDriftUs,
  };

  /// Maximum drift across a list of dispatched steps, in microseconds.
  static int maxDriftUs(List<DispatchedStep> dispatched) {
    var max = 0;
    for (final step in dispatched) {
      if (step.driftUs.abs() > max) max = step.driftUs.abs();
    }
    return max;
  }

  /// Independently versioned facets (they evolve at different rates;
  /// receipts pin which shape produced a stream).
  static const Map<String, String> facetVersions = {
    'plan': 'behavior.plan/v2',
    'timing': 'timing/v1',
    'pointerMotion': 'pointerMotion/v1',
    'keystrokeCadence': 'keystrokeCadence/v1',
    'actionRhythm': 'actionRhythm/v1',
    'reactionDelay': 'reactionDelay/v1',
    'sessionPacing': 'sessionPacing/v1',
  };
}
