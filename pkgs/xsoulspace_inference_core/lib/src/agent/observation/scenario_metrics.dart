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
  });
  final String actor;
  final String prompt;
  final int tokensUsed;
  final int projectedBeats;
  final List<String> explicitAbsences;
  final int llmCalls;
  final bool truncated;
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
  }) : telemetry = telemetry ?? MetricsReport(decisions: const []);
  final String name;
  final List<DecisionMetrics> decisions;
  final int totalLlmCalls;
  final int totalTokens;
  final int prunedThreads;
  final int mergedThreads;

  /// Richer telemetry (tool calls/results, trends) from [MetricsCollector].
  final MetricsReport telemetry;

  double get avgTokensPerDecision =>
      decisions.isEmpty ? 0 : totalTokens / decisions.length;
  double get avgLlmCallsPerDecision =>
      decisions.isEmpty ? 0 : totalLlmCalls / decisions.length;
}
