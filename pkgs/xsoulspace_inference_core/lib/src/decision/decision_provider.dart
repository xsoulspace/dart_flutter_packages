import 'decision_models.dart';

/// Optional bounded-decision capability, independent from [InferenceClient].
///
/// Consumers construct and bind an implementation explicitly. Capability and
/// readiness getters are local snapshots and must not perform network I/O.
abstract interface class DecisionProvider {
  String get id;

  DecisionProviderCapabilities get capabilities;

  DecisionProviderReadiness get readiness;

  Future<DecisionOutcome> decide(DecisionRequest request);

  /// Cancels only requests carrying [cancellationId].
  Future<void> cancel(DecisionCancellationId cancellationId);

  Future<void> dispose();
}
