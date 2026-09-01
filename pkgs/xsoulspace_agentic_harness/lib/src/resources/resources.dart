import 'dart:async';

import 'package:ecsly/ecsly.dart';

import '../events.dart';
import '../model_router.dart';
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

/// Executor for a tool, resolved by name.
///
/// Keeps tool execution out of the graph: [ToolDefinition]s (pure data) can
/// live as beats/props and be snapshot/restored, while closures stay in this
/// resource. When no executor is registered for a name,
/// [toolExecutionSystem] falls back to the registry's inline closure.
typedef ToolExecutor = Future<Object?> Function(Object? args);

/// World resource mapping tool names to executors.
class ToolExecutorResource extends Resource {
  final Map<ToolName, ToolExecutor> _executors = {};

  void register(ToolName name, ToolExecutor executor) =>
      _executors[name] = executor;

  void registerAll(Iterable<ToolDef> tools) {
    for (final tool in tools) {
      _executors[tool.name] = (args) async => tool.execute(args);
    }
  }

  ToolExecutor? get(ToolName name) => _executors[name];
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

/// Agency policy: how to prioritize competing agency grants and how to
/// bound in-flight work.
class AgencyPolicy extends Resource {
  AgencyPolicy({
    this.maxConcurrent = 8,
    this.maxRetries = 3,
    this.taskTimeout = const Duration(minutes: 5),
    this.maxToolRounds = 16,
    this.maxGoalAttempts = 3,
  });

  /// Maximum number of actors that may hold [Agency] in a single tick.
  int maxConcurrent;

  /// Maximum retry attempts for an empty/failed LLM response before the
  /// decision is dropped.
  int maxRetries;

  /// How long a generation or tool task may stay in flight before the
  /// harness fails it and frees the actor.
  ///
  /// [Duration.zero] disables the timeout (not recommended — a crashed
  /// backend would hang the actor and the loop forever).
  Duration taskTimeout;

  /// Maximum tool→continuation rounds per decision chain. Bounds the ReAct
  /// loop (ADR 0004): after this many continuation decisions spawned by tool
  /// results, the chain is dropped instead of continued. Prevents a model
  /// that never stops calling tools from looping forever.
  int maxToolRounds;

  /// Maximum failed goal verifications before the repair loop STOPS
  /// re-prompting (J1.5.1). On exhaustion the policy stamps
  /// [GoalAttemptsExhausted] + [EscalationRequest] with a structured reason
  /// and suspends the actor's threads — the bottom rung of the J8 ladder.
  /// Monotonic [AttemptCount] is NEVER reset by prose turns, so this is a
  /// hard bound on fix→fail→fix cycling.
  int maxGoalAttempts;
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

/// Push channel for streaming deltas — the host-facing side of streaming.
///
/// Handlers publish deltas here as they arrive (same tick); hosts subscribe
/// per actor and render incrementally:
///
/// - **Flutter**: wrap in a `StreamBuilder` on `subscribe(actorEntity)`.
/// - **TUI/CLI**: subscribe and print to stdout.
/// - The world-side [StreamingBeat] component remains the authoritative
///   accumulated buffer; this resource is a live push tap, not storage.
class StreamingTapResource extends Resource {
  final Map<Entity, StreamController<String>> _controllers = {};

  /// Subscribe to streamed text for [actor]. Multiple subscribers are
  /// supported (broadcast). The stream closes when the actor's turn completes
  /// or the actor despawns.
  Stream<String> subscribe(Entity actor) => _controllerFor(actor).stream;

  /// Publish a delta for [actor]. Called by handlers; no-op if nobody is
  /// listening (streaming still accumulates into [StreamingBeat]).
  void publish(Entity actor, String delta) {
    final controller = _controllers[actor];
    if (controller != null && !controller.isClosed) {
      controller.add(delta);
    }
  }

  /// Close the tap for [actor] — called when its response lands.
  Future<void> close(Entity actor) async {
    await _controllers.remove(actor)?.close();
  }

  /// Close all taps (world teardown / scenario switch).
  Future<void> closeAll() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }

  StreamController<String> _controllerFor(Entity actor) => _controllers
      .putIfAbsent(actor, StreamController<String>.broadcast);
}
