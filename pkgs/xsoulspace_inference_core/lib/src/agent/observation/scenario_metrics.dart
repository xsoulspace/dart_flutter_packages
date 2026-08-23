import 'metrics.dart';

/// Metrics for one decision (one agency moment).
class DecisionMetrics {
  DecisionMetrics({
    required this.actor,
    required this.prompt,
    required this.tokensUsed,
    required this.projectedBeats,
    required this.explicitAbsences,
    required this.llmCalls,
    required this.truncated,
    this.projectedTexts = const [],
  });
  final String actor;
  final String prompt;
  final int tokensUsed;
  final int projectedBeats;
  final List<String> explicitAbsences;
  final int llmCalls;
  final bool truncated;

  /// Exact texts of the beats in this decision's cut, captured at projection
  /// time (ADR 0004). Empty for metrics produced by older runners.
  final List<String> projectedTexts;
}

/// Aggregate metrics for a whole [Scenario] run.
class ScenarioMetrics {
  ScenarioMetrics({
    required this.name,
    required this.decisions,
    required this.totalLlmCalls,
    required this.totalTokens,
    required this.prunedThreads,
    required this.mergedThreads,
    MetricsReport? telemetry,
    this.policyPrecision = const {},
  }) : telemetry = telemetry ?? MetricsReport(decisions: const []);
  final String name;
  final List<DecisionMetrics> decisions;
  final int totalLlmCalls;
  final int totalTokens;
  final int prunedThreads;
  final int mergedThreads;

  /// Richer telemetry (tool calls/results, trends) from [MetricsCollector].
  final MetricsReport telemetry;

  /// Per-policy agency precision (ADR 0005): policy name →
  /// (created, answered). A decision counts as answered when it produced a
  /// response (no retries pending). Empty when the run used no
  /// DecisionFlow-originated decisions.
  final Map<String, ({int created, int answered})> policyPrecision;

  /// Precision per policy: answered / created (0–1). Policies with zero
  /// created decisions are omitted.
  Map<String, double> get policyPrecisionRate => {
    for (final entry in policyPrecision.entries)
      if (entry.value.created > 0)
        entry.key: entry.value.answered / entry.value.created,
  };

  double get avgTokensPerDecision =>
      decisions.isEmpty ? 0 : totalTokens / decisions.length;
  double get avgLlmCallsPerDecision =>
      decisions.isEmpty ? 0 : totalLlmCalls / decisions.length;
}
