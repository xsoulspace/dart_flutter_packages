import 'package:ecsly/ecsly.dart';

import '../agent_low_api.dart';
import '../events.dart';
import '../tools/tools.dart';

export 'task_registry.dart';

// ─────────────────────────────────────────────
// Resources
// ─────────────────────────────────────────────

/// World resource holding the model router for runtime-swappable LLMs.
///
/// Wraps the existing [ModelRouter] from agent.dart. Actors reference models
/// by [ModelId]; this resource resolves them to [ModelRuntime] instances.
class ModelRouterResource extends Resource {
  ModelRouterResource(this.router);
  final ModelRouter router;
}

/// World resource holding named tool registries.
///
/// Actors reference a registry by name via [ActorTools].
class ToolRegistryResource extends Resource {
  final Map<String, ToolRegistry> registries = {};

  ToolRegistry? get(String name) => registries[name];

  void register(String name, ToolRegistry registry) {
    registries[name] = registry;
  }
}

/// Token estimator for projection budgeting.
typedef TokenEstimator = int Function(String text);

/// Default estimator: ~4 chars per token.
int defaultTokenEstimator(String text) => (text.length / 4).ceil();

/// World resource holding the projection token budget.
///
/// Projection systems use this to keep the model's view within the tiny
/// context window. Content that does not fit is dropped (green screen).
class ProjectionBudget extends Resource {
  ProjectionBudget({this.tokens = 4000, this.estimator});
  int tokens;
  final TokenEstimator? estimator;
}

/// World resource holding projection policy (relevance / cut rules).
class ProjectionPolicy extends Resource {
  ProjectionPolicy({
    this.maxBeats = 8,
    this.includePartials = true,
    this.greenScreen = true,
    this.maxProps = 8,
    this.maxCoPresent = 4,
  });
  int maxBeats;
  bool includePartials;
  bool greenScreen;
  int maxProps;
  int maxCoPresent;
}

/// Agency policy: how to prioritize competing agency grants.
class AgencyPolicy extends Resource {
  AgencyPolicy({this.maxConcurrent = 8});

  /// Maximum number of actors that may hold [Agency] in a single tick.
  int maxConcurrent;
}

/// World resource routing generation requests to handlers.
///
/// Resolution order: per-agent, then per-model, then default. This is what
/// makes "several handlers, several LLMs, several I/O operations" fall out
/// naturally — the world does not care whether a handler is an LLM, a human,
/// or another agent.
class GenerationHandlerResource extends Resource {
  GenerationHandler? defaultHandler;
  final Map<AgentId, GenerationHandler> byAgent = {};
  final Map<ModelId, GenerationHandler> byModel = {};

  GenerationHandler? resolve(ActorGenerateRequest request) =>
      byAgent[request.agentId] ?? byModel[request.modelId] ?? defaultHandler;

  void registerDefault(GenerationHandler handler) => defaultHandler = handler;
  void registerForAgent(AgentId agentId, GenerationHandler handler) =>
      byAgent[agentId] = handler;
  void registerForModel(ModelId modelId, GenerationHandler handler) =>
      byModel[modelId] = handler;
}
