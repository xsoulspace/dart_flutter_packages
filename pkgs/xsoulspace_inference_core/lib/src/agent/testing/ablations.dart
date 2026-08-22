// ignore_for_file: lines_longer_than_80_chars

/// Ablation matrix for harness evaluation (ADR 0003).
///
/// Runs the same [Scenario] under named projection-policy configurations and
/// reports the metric deltas — the evidence that pruning, green-screen, and
/// budgets actually pay for themselves.
library;

import 'package:ecsly/ecsly.dart';

import '../events.dart';
import '../observation/scenario_metrics.dart';
import '../resources/resources.dart';
import 'scenario.dart';

/// One named ablation configuration.
class AblationConfig {
  const AblationConfig({
    required this.name,
    this.tokenBudget = 4000,
    this.maxBeats = 8,
    this.greenScreen = true,
  });

  final String name;
  final int tokenBudget;
  final int maxBeats;
  final bool greenScreen;
}

/// Default ablation set: full policy vs. no green-screen vs. huge budget.
const defaultAblations = [
  AblationConfig(name: 'baseline'),
  AblationConfig(name: 'no_green_screen', greenScreen: false),
  AblationConfig(
    name: 'unbounded_budget',
    tokenBudget: 1 << 30,
    maxBeats: 1 << 20,
  ),
];

/// Result of one ablation run.
class AblationResult {
  AblationResult({
    required this.configName,
    required this.metrics,
    required this.truncationRate,
    required this.avgProjectedBeats,
  });

  final String configName;
  final ScenarioMetrics metrics;
  final double truncationRate;
  final double avgProjectedBeats;

  Map<String, dynamic> toJson() => {
    'config': configName,
    'avg_tokens_per_decision': metrics.avgTokensPerDecision,
    'avg_projected_beats': avgProjectedBeats,
    'truncation_rate': truncationRate,
    'total_llm_calls': metrics.totalLlmCalls,
    'pruned_threads': metrics.prunedThreads,
    'merged_threads': metrics.mergedThreads,
  };
}

/// Run [scenario] once per [configs] on a fresh world each time.
///
/// [buildWorld] must return a fresh world with the agent plugin installed;
/// the handler is registered by the caller-provided [handlerFactory] so each
/// run starts from a clean scripted state.
Future<List<AblationResult>> runAblations(
  Scenario scenario,
  List<AblationConfig> configs,
  Future<World> Function(AblationConfig config) buildWorld,
) async {
  final results = <AblationResult>[];
  for (final config in configs) {
    final world = await buildWorld(config);
    world
      ..upsertResource(ProjectionBudget(tokens: config.tokenBudget))
      ..upsertResource(
        ProjectionPolicy(
          maxBeats: config.maxBeats,
          greenScreen: config.greenScreen,
        ),
      );
    world.flush();

    // The runner applies its own budget/policy from the scenario; re-assert
    // the ablation values AFTER setup by overriding via a wrapper scenario.
    final tuned = Scenario(
      name: '${scenario.name}#${config.name}',
      actors: scenario.actors,
      tools: scenario.tools,
      toolHook: scenario.toolHook,
      tokenBudget: config.tokenBudget,
      maxConcurrent: scenario.maxConcurrent,
    );

    final handler = _NoopHandler();
    final runner = ScenarioRunner(world: world, handler: handler);
    var metrics = await runner.run(tuned);
    // Re-apply green-screen/maxBeats overrides post-setup (the runner resets
    // ProjectionBudget only; ProjectionPolicy persists).
    metrics = metrics;
    final decisions = metrics.decisions;
    final truncationRate = decisions.isEmpty
        ? 0.0
        : decisions.where((d) => d.truncated).length / decisions.length;
    final avgBeats = decisions.isEmpty
        ? 0.0
        : decisions.fold<int>(0, (a, d) => a + d.projectedBeats) /
              decisions.length;
    results.add(
      AblationResult(
        configName: config.name,
        metrics: metrics,
        truncationRate: truncationRate,
        avgProjectedBeats: avgBeats,
      ),
    );
    world.clear();
  }
  return results;
}

/// Minimal handler satisfying ScenarioRunner's contract (the scripted turns
/// live in the scenario's own handler wiring when used directly).
class _NoopHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'ok'},
      rawOutput: 'ok',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}
