import 'dart:async';
import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';
import 'package:meta/meta.dart';

import '../models/inference_models.dart';
import 'agent.dart';
import 'narrative.dart';

// ─────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────

/// Identity component for an actor entity.
///
/// An Actor entity represents an agent identity (LLM, human, or other).
/// The [agentId] is a stable domain key; the entity itself is the
/// runtime handle.
class Actor implements Component {
  const Actor({required this.agentId});
  final AgentId agentId;
}

/// Current model binding for an actor.
///
/// Swapping this component at runtime changes which model the actor
/// uses on its next generation. The [modelId] resolves through
/// [ModelRouterResource].
class ActorModel implements Component {
  const ActorModel({required this.modelId});
  final ModelId modelId;
}

/// System prompt for an actor.
class ActorSystemPrompt implements Component {
  const ActorSystemPrompt({required this.text});
  final String text;
}

/// Name of the tool registry this actor can use.
///
/// Resolved through [ToolRegistryResource] at generation time.
class ActorTools implements Component {
  const ActorTools({required this.registryName});
  final String registryName;
}

/// Per-actor runtime conversation memory.
///
/// Stored as a list of context fragments (system, user, model, tool).
/// This is cold-path data — not in the hot loop.
///
/// Each fragment references a [Beat] entity in the narrative graph,
/// enabling typed access to content via the Beat's modality components.
class ActorRuntimeMemories implements Component {
  ActorRuntimeMemories({List<ContextFragment>? fragments})
    : fragments = fragments ?? <ContextFragment>[];

  List<ContextFragment> fragments;
}

/// A single context fragment in an actor's memory.
///
/// References a [Beat] entity in the narrative graph. The Beat's
/// modality-specific components (TextContent, BeatToolCall, etc.)
/// provide the actual content.
class ContextFragment {
  const ContextFragment({required this.type, required this.beat});
  final ContextFragmentType type;
  final Entity beat;
}

/// Links an actor to the thread(s) that constitute its memory.
///
/// Memory is a result of the storyline, not the other way around. This
/// component points the actor at the thread(s) whose beats make up its
/// observable history. [ActorRuntimeMemories.fragments] is a *derived
/// cache* over these threads — rebuilt by the compaction/rebuild system,
/// never an independent source of truth.
class ActorMemoryRef implements Component {
  ActorMemoryRef({List<Entity>? threads}) : threads = threads ?? <Entity>[];

  /// The threads this actor's memory is derived from.
  List<Entity> threads;
}

/// Persist the actor's current memory path so it survives a rebuild in a
/// subsequent tick or schedule run.
///
/// Mechanical. Walks each thread's beats and rewrites
/// [ActorRuntimeMemories.fragments] to match the thread graph. This is the
/// single place memory is re-derived from the storyline.
Entity persistMemory(World world, Entity actorEntity) {
  final we = world.getEntity(actorEntity).$1;
  we.insert(ActorRuntimeMemories(fragments: _threadFragments(world, we)));
  return actorEntity;
}

/// Link [actorEntity] memory to the given [thread]s.
void linkActorToThreads(World world, Entity actorEntity, List<Entity> threads) {
  final we = world.getEntity(actorEntity).$1;
  we.insert(ActorMemoryRef(threads: threads));
}

/// Derives the actor's memory fragments from its linked threads.
List<ContextFragment> _threadFragments(World world, WorldEntity actorEntity) {
  final ref = actorEntity.get<ActorMemoryRef>();
  if (ref == null) return const [];

  final out = <ContextFragment>[];
  for (final thread in ref.threads) {
    final (t, valid) = world.getEntity(thread);
    if (!valid) continue;
    for (final (beat, belongs, _)
        in world.query2<BelongsToThread, BeatStatus>()) {
      if (belongs.thread == thread) {
        out.add(ContextFragment(type: _tagFor(beat), beat: beat.entity));
      }
    }
  }
  return out;
}

ContextFragmentType _tagFor(WorldEntity beat) {
  if (beat.has<MemorySummary>()) return ContextFragmentType.memorySummary;
  if (beat.has<BeatToolCall>()) return ContextFragmentType.toolMessage;
  return ContextFragmentType.modelResponse;
}

/// Tag component: this actor currently has agency and must act.
///
/// Granted by [grantAgencySystem] when an [OpenDecision] exists.
/// Consumed by [processResponsesSystem] after the actor responds.
class Agency implements Component {
  const Agency();
}

/// Tag component: this actor has dispatched an async request and is waiting
/// for a response.
///
/// Added by [actorActSystem] when the request is dispatched. Consumed by
/// [processResponsesSystem] after the response is processed.
/// Prevents re-granting Agency until the response arrives.
///
/// [taskId] correlates the actor to the in-flight task in
/// [TaskRegistryResource], so one actor can await an LLM, a tool, and a
/// human input simultaneously.
class AwaitingResponse implements Component {
  const AwaitingResponse({this.taskId});
  final TaskId? taskId;
}

/// Explicit signal that agency is required.
///
/// An entity with both [Actor] and [OpenDecision] (and no [Agency] yet)
/// triggers the agency-granting system. The [schema] describes the
/// expected structured output; empty schema means free text.
///
/// [priority] ranks competing decisions (higher = more urgent). [escalate]
/// requests a stronger model for this decision (Phase 3).
class OpenDecision implements Component {
  const OpenDecision({
    this.schema = SchemaBundle.empty,
    this.prompt = '',
    this.priority = 0,
    this.escalate = false,
  });
  final SchemaBundle schema;
  final String prompt;
  final int priority;
  final bool escalate;
}

/// Tag component: this actor has requested escalation to a stronger model.
///
/// Written by a mechanical system when an [OpenDecision] has
/// [OpenDecision.escalate] set (or the local model signals low confidence).
/// The agency system routes this actor's next generation to a different
/// (larger) model, then folds the result back into the narrative state.
class EscalationRequest implements Component {
  const EscalationRequest({this.reason = ''});
  final String reason;
}

/// Agency policy: how to prioritize competing agency grants.
class AgencyPolicy extends Resource {
  AgencyPolicy({this.maxConcurrent = 8});

  /// Maximum number of actors that may hold [Agency] in a single tick.
  int maxConcurrent;
}

/// Tag component: this entity is a Scene (the current stage).
class Scene implements Component {
  const Scene();
}

/// Frame counter for the current scene.
class SceneFrame implements Component {
  SceneFrame({this.frame = 0});
  int frame;
}

/// Relationship: an actor is present in a scene.
///
/// [sceneEntity] points to the Scene entity.
class PresentInScene implements Component {
  const PresentInScene({required this.sceneEntity});
  final Entity sceneEntity;
}

/// Relationship: a prop is present in a scene.
class PresentProp implements Component {
  const PresentProp({required this.sceneEntity});
  final Entity sceneEntity;
}

/// A prop is any mutable stateful object (file, memory, tool result, etc.).
class Prop implements Component {
  const Prop({required this.name});
  final String name;
}

/// Transient minimal projection prepared for one actor.
///
/// A cinematic cut, not a summary: only the props in frame, co-present
/// actors, the local question, the projected (budget-limited) context beats,
/// and explicit absences. Built by [projectSituationSystem] and consumed by
/// [actorActSystem].
class Situation implements Component {
  Situation({
    this.prompt = '',
    this.schema = SchemaBundle.empty,
    this.inFramePropIds = const [],
    this.coPresentActorIds = const [],
    this.contextFragments = const [],
    this.explicitAbsences = const [],
    this.toolRegistryName,
    this.tokensUsed = 0,
    this.tokenBudget = 4000,
    this.truncated = false,
  });
  String prompt;
  SchemaBundle schema;
  List<String> inFramePropIds;
  List<AgentId> coPresentActorIds;

  /// The projected, relevance-ranked, budget-limited context beats the model
  /// will actually see. This is the cinematic cut.
  List<ContextFragment> contextFragments;

  /// Green-screen: explicit statements of what the model does NOT see.
  List<String> explicitAbsences;

  /// The tool registry in frame for this actor (if any).
  String? toolRegistryName;

  /// Tokens consumed by this projection (for measurement / budget audit).
  int tokensUsed;

  /// The token budget this projection was built against.
  int tokenBudget;

  /// True when relevant context was omitted to fit the budget.
  bool truncated;
}

/// A goal assigned to an actor.
class Goal implements Component {
  Goal({this.text = ''});
  String text;
}

/// Partial streaming buffer for an actor's in-progress generation.
///
/// Chunks are appended by [processStreamEventsSystem] as the handler
/// streams them. UI can read this component to render partials live;
/// the final response is stored as a Beat by [processResponsesSystem].
class StreamingBeat implements Component {
  StreamingBeat({List<String>? chunks}) : chunks = chunks ?? <String>[];
  final List<String> chunks;
}

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

// ─────────────────────────────────────────────
// Bounded memory (Phase 2)
// ─────────────────────────────────────────────

/// A memory summary: a compact, queryable record of an actor's past work.
///
/// Mechanical systems write these from raw beats so the actor's projected
/// context never has to carry full history. The summary is a Prop — it can
/// be observed, shared, and referenced by other actors.
class MemorySummary implements Component {
  MemorySummary(this.text);
  String text;
}

/// The actor this memory summary belongs to.
class SummaryOwner implements Component {
  const SummaryOwner(this.actor);
  final Entity actor;
}

/// The thread this summary was derived from (if any).
class SummaryThread implements Component {
  const SummaryThread(this.thread);
  final Entity? thread;
}

/// A memory compaction policy: when to compact and how much to keep.
class MemoryCompactionPolicy extends Resource {
  MemoryCompactionPolicy({
    this.maxRawFragments = 12,
    this.summaryEvery = 8,
    this.summaryLength = 200,
  });

  /// Above this many raw fragments, compaction starts.
  int maxRawFragments;

  /// Compact the oldest N raw fragments into one summary every N beats.
  int summaryEvery;

  /// Max chars for a generated summary.
  int summaryLength;
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

/// Identity for an in-flight async task (LLM generation, tool call, human
/// input). Tasks are correlated across the world via [TaskRegistryResource].
@immutable
class TaskId {
  const TaskId(this.value);
  factory TaskId.create() => TaskId('${DateTime.now().microsecondsSinceEpoch}');
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TaskId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Cold handle to an in-flight task.
///
/// Holds the [Completer] that resumes the awaiting caller (e.g. a native
/// tool bridge or a host awaiting an actor response). Completers live here —
/// in a cold resource — never in a component, keeping the ECS hot path
/// future-free.
class TaskHandle {
  TaskHandle({Completer<dynamic>? completer})
    : completer = completer ?? Completer<dynamic>();
  final Completer<dynamic> completer;
}

/// World resource tracking in-flight async tasks.
///
/// This is the single source of truth for "is there pending async work".
/// [HarnessLoop.canSleep] checks it; systems resolve tasks by completing
/// the associated [TaskHandle.completer].
class TaskRegistryResource extends Resource {
  final Map<TaskId, TaskHandle> _tasks = {};

  void register(TaskId id, TaskHandle handle) => _tasks[id] = handle;

  TaskHandle? take(TaskId id) => _tasks.remove(id);

  TaskHandle? peek(TaskId id) => _tasks[id];

  bool has(TaskId id) => _tasks.containsKey(id);

  int get length => _tasks.length;

  bool get isEmpty => _tasks.isEmpty;
}

/// A handler that performs an async generation for an actor.
///
/// Implementations live outside the core (Flutter isolate, CLI, another
/// agent, a human channel). The world dispatches to them via
/// [GenerationHandlerResource]; they send results back as
/// [ActorGenerateResponse] events.
///
/// This replaces the old polled [ActorGenerateHandler]. Handlers are now
/// resources the world *uses*, not objects the world is polled by.
abstract class GenerationHandler {
  /// Perform the generation and send an [ActorGenerateResponse] back to
  /// [world]'s event channel. May send [ActorGenerateStreamEvent]s first.
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  );
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

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// Request to generate LLM output for an actor.
///
/// Dispatched by [actorActSystem] to a [GenerationHandler] resolved via
/// [GenerationHandlerResource]. [taskId] correlates the request to the
/// in-flight task in [TaskRegistryResource].
class ActorGenerateRequest implements EcsEvent {
  const ActorGenerateRequest({
    required this.actorEntity,
    required this.agentId,
    required this.modelId,
    required this.prompt,
    required this.systemPrompt,
    required this.contextFragments,
    required this.schema,
    required this.toolRegistry,
    required this.task,
    required this.taskId,
  });

  final Entity actorEntity;
  final AgentId agentId;
  final ModelId modelId;
  final String prompt;
  final String systemPrompt;
  final List<Object> contextFragments;
  final SchemaBundle schema;
  final ToolRegistry? toolRegistry;
  final InferenceTask task;
  final TaskId taskId;
}

/// Response from a [GenerationHandler] back to the ECS world.
///
/// [toolCalls] contains parsed tool calls if the model emitted any.
/// [toolResults] contains results of tool calls that were already executed
/// natively (e.g. Apple Foundation). [taskId] matches the originating
/// [ActorGenerateRequest].
class ActorGenerateResponse implements EcsEvent {
  const ActorGenerateResponse({
    required this.actorEntity,
    required this.structuralOutput,
    required this.rawOutput,
    this.toolCalls = const [],
    this.toolResults = const [],
    this.taskId,
  });

  final Entity actorEntity;
  final Map<String, dynamic> structuralOutput;
  final String rawOutput;
  final List<ToolCall> toolCalls;
  final List<ToolExecutionResult> toolResults;
  final TaskId? taskId;
}

/// Streaming chunk from a handler during generation.
///
/// Appended to the actor's [StreamingBeat] by [processStreamEventsSystem].
class ActorGenerateStreamEvent implements EcsEvent {
  const ActorGenerateStreamEvent({
    required this.actorEntity,
    required this.taskId,
    required this.chunk,
  });

  final Entity actorEntity;
  final TaskId taskId;
  final String chunk;
}

/// A parsed tool call from an LLM response.
class ToolCall {
  const ToolCall({required this.name, required this.arguments});
  final ToolName name;
  final Map<String, dynamic> arguments;
}

/// Result of a tool call execution.
class ToolExecutionResult {
  const ToolExecutionResult({required this.name, required this.output});
  final String name;
  final dynamic output;
}

/// Event: a tool call that needs to be executed by the ECS world.
///
/// Sent by [processResponsesSystem] (for parsed tool calls) or by
/// [WorldToolBridge] (for native tool calls during generation).
/// Processed by [toolExecutionSystem] in the Mechanical schedule.
///
/// When [taskId] is present, [toolExecutionSystem] resolves the associated
/// [TaskHandle] after execution — this is how native tool calls suspend and
/// resume through the world.
class ToolCallEvent implements EcsEvent {
  const ToolCallEvent({
    required this.actorEntity,
    required this.call,
    this.taskId,
  });
  final Entity actorEntity;
  final ToolCall call;
  final TaskId? taskId;
}

/// Event: a tool call result that has been executed.
///
/// Sent by [toolExecutionSystem] after executing a [ToolCallEvent].
/// Consumed by [processToolResultsSystem] to store as a Beat.
class ToolResultEvent implements EcsEvent {
  const ToolResultEvent({required this.actorEntity, required this.result});
  final Entity actorEntity;
  final ToolExecutionResult result;
}

// ─────────────────────────────────────────────
// World tool bridge (Bevy-style task)
// ─────────────────────────────────────────────

/// Routes every tool call through the ECS world.
///
/// Wraps a [ToolRegistry] so that when a backend executes a tool natively
/// (e.g. Apple Foundation), the call is sent to the world as a
/// [ToolCallEvent], the caller suspends on a [Completer], and resumes when
/// [toolExecutionSystem] resolves the task. This unifies native and raw
/// tool lifecycles — the world is the backbone, not the backend.
class WorldToolBridge {
  WorldToolBridge({
    required this.world,
    required this.actorEntity,
    required this.source,
  });

  final World world;
  final Entity actorEntity;
  final ToolRegistry source;

  /// Build a [ToolRegistry] whose tool executions route through the world.
  ToolRegistry buildRegistry() {
    final bridged = ToolRegistry();
    for (final tool in source.tools.values) {
      bridged.register(
        ToolDef(
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters,
          execute: (args) => _routeToolCall(tool, args),
        ),
      );
    }
    return bridged;
  }

  Future<Object?> _routeToolCall(ToolDef tool, Object? args) {
    final taskId = TaskId.create();
    final completer = Completer<dynamic>();
    world.getResource<TaskRegistryResource>().register(
      taskId,
      TaskHandle(completer: completer),
    );

    world.events.writer<ToolCallEvent>().send(
      ToolCallEvent(
        actorEntity: actorEntity,
        call: ToolCall(name: tool.name, arguments: _asMap(args)),
        taskId: taskId,
      ),
    );

    return completer.future;
  }

  static Map<String, dynamic> _asMap(Object? args) {
    if (args is Map<String, dynamic>) return args;
    if (args is Map) {
      return args.map((k, v) => MapEntry('$k', v));
    }
    return {'value': args};
  }
}

// ─────────────────────────────────────────────
// Plugin
// ─────────────────────────────────────────────

/// Plugin that installs the agent harness into an ecsly [World].
///
/// Registers all components, resources, event channels, and the core
/// schedules for the cinematic multi-actor loop.
class AgentPlugin extends Plugin {
  @override
  void install(World world) {
    // Install async parallel plugin for ScheduleJobResultQueueResource
    world.addPlugin(const AsyncParallelPlugin());

    world.components
      ..registerObjectComponent<Actor>()
      ..registerObjectComponent<ActorModel>()
      ..registerObjectComponent<ActorSystemPrompt>()
      ..registerObjectComponent<ActorTools>()
      ..registerObjectComponent<ActorRuntimeMemories>()
      ..registerObjectComponent<ActorMemoryRef>()
      ..registerObjectComponent<Agency>()
      ..registerObjectComponent<AwaitingResponse>()
      ..registerObjectComponent<OpenDecision>()
      ..registerObjectComponent<EscalationRequest>()
      ..registerObjectComponent<Scene>()
      ..registerObjectComponent<SceneFrame>()
      ..registerObjectComponent<PresentInScene>()
      ..registerObjectComponent<PresentProp>()
      ..registerObjectComponent<Prop>()
      ..registerObjectComponent<Situation>()
      ..registerObjectComponent<Goal>()
      ..registerObjectComponent<StreamingBeat>()
      // Thread & Beat ontology (from narrative.dart)
      ..registerObjectComponent<Thread>()
      ..registerObjectComponent<ThreadScore>()
      ..registerObjectComponent<ThreadId>()
      ..registerObjectComponent<ThreadStatus>()
      ..registerObjectComponent<ParentScene>()
      ..registerObjectComponent<OriginActor>()
      ..registerObjectComponent<GoalLink>()
      ..registerObjectComponent<DerivedFromThread>()
      ..registerObjectComponent<ThreadVisibility>()
      ..registerObjectComponent<BeatId>()
      ..registerObjectComponent<BelongsToThread>()
      ..registerObjectComponent<BeatSequence>()
      ..registerObjectComponent<Speaker>()
      ..registerObjectComponent<AddressedTo>()
      ..registerObjectComponent<BeatModality>()
      ..registerObjectComponent<BeatStatus>()
      ..registerObjectComponent<ReplyToBeat>()
      ..registerObjectComponent<ObservesProp>()
      ..registerObjectComponent<PrivateToActor>()
      ..registerObjectComponent<TextContent>()
      ..registerObjectComponent<TextStream>()
      ..registerObjectComponent<AudioStream>()
      ..registerObjectComponent<ActionPayload>()
      ..registerObjectComponent<BeatToolCall>()
      ..registerObjectComponent<ToolResult>()
      ..registerObjectComponent<ThoughtContent>()
      ..registerObjectComponent<ObservationData>()
      // Bounded memory (Phase 2)
      ..registerObjectComponent<MemorySummary>()
      ..registerObjectComponent<SummaryOwner>()
      ..registerObjectComponent<SummaryThread>();

    // Resources
    world
      ..upsertResource(TaskRegistryResource())
      ..upsertResource(GenerationHandlerResource())
      ..upsertResource(ProjectionBudget())
      ..upsertResource(ProjectionPolicy())
      ..upsertResource(MemoryCompactionPolicy())
      ..upsertResource(AgencyPolicy());

    // Event channels for async LLM I/O
    world.events.register<ActorGenerateRequest>();
    world.events.register<ActorGenerateResponse>();
    world.events.register<ActorGenerateStreamEvent>();
    world.events.register<ToolCallEvent>();
    world.events.register<ToolResultEvent>();

    // Schedules — the cinematic multi-actor loop
    //
    // 1. AgencyGrant: grant Agency to actors with OpenDecision
    // 2. Project: build minimal Situations for actors with Agency
    // 3. ActorAct: dispatch generation requests (fire-and-forget)
    // 4. ProcessResponses: handle LLM responses, dispatch tool calls
    // 5. Mechanical: execute tools, score/prune threads
    // 6. Narrative: advance Thread/Beat playheads, finalize partials
    world.createSchedule('AgencyGrant')
      ..add(grantAgencySystem, name: 'grantAgency')
      ..then(flushAllSystem, name: 'flushAfterGrant');

    world.createSchedule('Project')
      ..add(projectSituationSystem, name: 'projectSituation')
      ..then(flushAllSystem, name: 'flushAfterProject');

    world.createSchedule('ActorAct')
      ..add(actorActSystem, name: 'actorAct', mode: ExecutionMode.asyncParallel)
      ..then(flushAllSystem, name: 'flushAfterAct');

    world.createSchedule('ProcessResponses')
      ..add(processStreamEventsSystem, name: 'processStreamEvents')
      ..then(processResponsesSystem, name: 'processResponses')
      ..then(flushAllSystem, name: 'flushAfterResponses');

    world.createSchedule('Mechanical')
      ..add(toolExecutionSystem, name: 'toolExecution')
      ..then(processToolResultsSystem, name: 'processToolResults')
      ..then(scoreThreadsSystem, name: 'scoreThreads')
      ..then(pruneThreadsSystem, name: 'pruneThreads')
      ..then(mergeThreadsSystem, name: 'mergeThreads')
      ..then(flushAllSystem, name: 'flushAfterMechanical');

    world.createSchedule('Narrative')
      ..add(finalizePartialsSystem, name: 'finalizePartials')
      ..then(compactMemorySystem, name: 'compactMemory')
      ..then(flushAllSystem, name: 'flushAfterNarrative');
  }

  @override
  String get name => 'agent-plugin';
}

// ─────────────────────────────────────────────
// Systems
// ─────────────────────────────────────────────

/// System 1: Grant agency to actors that have an [OpenDecision].
///
/// For each Actor entity with [OpenDecision] but without [Agency]
/// and without [AwaitingResponse], add the [Agency] tag.
/// This is the explicit agency-granting step — actors never assume
/// agency; systems grant it.
///
/// Prioritization: decisions with higher [OpenDecision.priority] or an
/// [EscalationRequest] are granted first. The number of concurrent grants
/// is capped by [AgencyPolicy.maxConcurrent] so a crowd of actors doesn't
/// flood the model pool.
void grantAgencySystem(World world) {
  final policy = world.getResource<AgencyPolicy>();
  final actorsWithDecisions = world.query2<Actor, OpenDecision>();

  // Collect eligible actors (have a decision, no agency, no pending response).
  final eligible = <(WorldEntity, OpenDecision)>[];
  for (final (entity, _, decision) in actorsWithDecisions) {
    if (entity.has<Agency>()) continue;
    if (entity.has<AwaitingResponse>()) continue;
    eligible.add((entity, decision));
  }

  // Sort by priority (desc), then escalation (escalated first).
  eligible.sort((a, b) {
    final byPriority = b.$2.priority.compareTo(a.$2.priority);
    if (byPriority != 0) return byPriority;
    final aEsc = a.$1.has<EscalationRequest>() || a.$2.escalate;
    final bEsc = b.$1.has<EscalationRequest>() || b.$2.escalate;
    return (bEsc ? 1 : 0).compareTo(aEsc ? 1 : 0);
  });

  // Grant up to the concurrency cap.
  var granted = 0;
  for (final (entity, _) in eligible) {
    if (granted >= policy.maxConcurrent) break;
    entity.insert(const Agency());
    granted++;
  }
}

/// System 2: Build a minimal [Situation] for each actor with [Agency].
///
/// Projection is ruthlessly minimal and cinematic — only props in frame,
/// co-present actors, and the local question. Context windows stay tiny.
/// System 2: Build a minimal [Situation] for each actor with [Agency].
///
/// Projection is ruthlessly minimal and cinematic — only props in frame,
/// co-present actors, the local question, and a relevance-ranked, budget-
/// limited slice of the actor's memory. Everything else stays off-screen
/// (green screen). Context windows stay tiny by design.
void projectSituationSystem(World world) {
  final budget = world.getResource<ProjectionBudget>();
  final policy = world.getResource<ProjectionPolicy>();
  final estimator = budget.estimator ?? defaultTokenEstimator;

  final actorsWithAgency = world.query3<Actor, Agency, ActorRuntimeMemories>();

  // Materialize the query results before mutating, since entity.insert()
  // changes archetypes and can invalidate lazy iterators.
  for (final (entity, actor, _, _) in actorsWithAgency.toList()) {
    final situation = _buildSituation(
      world: world,
      entity: entity,
      actor: actor,
      budget: budget.tokens,
      policy: policy,
      estimator: estimator,
    );
    entity.insert(situation);
  }
}

Situation _buildSituation({
  required World world,
  required WorldEntity entity,
  required Actor actor,
  required int budget,
  required ProjectionPolicy policy,
  required TokenEstimator estimator,
}) {
  // Find the current scene
  WorldEntity? sceneEntity;
  for (final (sceneEnt, _, _) in world.query2<Scene, SceneFrame>()) {
    sceneEntity = sceneEnt;
    break;
  }
  if (sceneEntity == null) return Situation(tokenBudget: budget);

  // Find co-present actors (same scene, excluding self), capped.
  final coPresent = <AgentId>[];
  for (final (_, present, otherActor)
      in world.query2<PresentInScene, Actor>()) {
    if (present.sceneEntity == sceneEntity.entity &&
        otherActor.agentId != actor.agentId) {
      coPresent.add(otherActor.agentId);
      if (coPresent.length >= policy.maxCoPresent) break;
    }
  }

  // Find props in frame, capped.
  final inFrameProps = <String>[];
  for (final (_, present, prop) in world.query2<PresentProp, Prop>()) {
    if (present.sceneEntity == sceneEntity.entity) {
      inFrameProps.add(prop.name);
      if (inFrameProps.length >= policy.maxProps) break;
    }
  }

  // The local question.
  final decision = entity.get<OpenDecision>();
  final prompt = decision?.prompt ?? '';

  // Cinematic cut: relevance-rank the actor's memory beats, then fit them
  // into the token budget. This is the intelligence amplifier — the model
  // only ever sees the slice the current decision actually needs.
  final memories = entity.get<ActorRuntimeMemories>();
  final fragments = memories?.fragments ?? const <ContextFragment>[];
  final ranked = _rankFragments(world, fragments, prompt);
  final fit = _fitToBudget(
    world: world,
    fragments: ranked,
    budget: budget,
    prompt: prompt,
    estimator: estimator,
    maxBeats: policy.maxBeats,
  );
  final selected = fit.selected;
  final tokensUsed = fit.tokensUsed;
  final truncated = fit.truncated;

  // Green-screen: explicit absences so the model knows what it does NOT see.
  final absences = <String>[];
  if (policy.greenScreen) {
    if (fragments.length > selected.length) {
      absences.add(
        '${fragments.length - selected.length} earlier beat(s) are off-screen.',
      );
    }
    if (truncated) {
      absences.add('Some context was cut to fit the token budget.');
    }
    if (coPresent.isEmpty) {
      absences.add('No other actors are in frame.');
    }
  }

  final tools = entity.get<ActorTools>();

  return Situation(
    prompt: prompt,
    schema: decision?.schema ?? SchemaBundle.empty,
    inFramePropIds: inFrameProps,
    coPresentActorIds: coPresent,
    contextFragments: selected,
    explicitAbsences: absences,
    toolRegistryName: tools?.registryName,
    tokensUsed: tokensUsed,
    tokenBudget: budget,
    truncated: truncated,
  );
}

/// Rank context fragments by relevance to the current [prompt].
///
/// A lightweight, deterministic heuristic: fragments whose text shares terms
/// with the prompt rank higher; recency breaks ties. This is the projection
/// system's job — the model never sees raw history, only the ranked cut.
List<ContextFragment> _rankFragments(
  World world,
  List<ContextFragment> fragments,
  String prompt,
) {
  final promptTerms = prompt
      .toLowerCase()
      .split(RegExp(r'\W+'))
      .where((t) => t.length > 2)
      .toSet();
  if (promptTerms.isEmpty) return fragments.reversed.toList();

  final scored = <(ContextFragment, int)>[];
  for (var i = 0; i < fragments.length; i++) {
    final f = fragments[i];
    final text = _fragmentText(world, f).toLowerCase();
    var score = 0;
    for (final term in promptTerms) {
      if (text.contains(term)) score++;
    }
    // Recency tie-break: later fragments win.
    scored.add((f, score * 1000 + i));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((s) => s.$1).toList();
}

/// Fit ranked fragments into the token budget, newest-relevant first.
///
/// Returns the selected fragments, tokens used, and whether anything was cut.
/// The prompt + system prompt are always included; beats are added until the
/// budget is exhausted.
({List<ContextFragment> selected, int tokensUsed, bool truncated})
_fitToBudget({
  required World world,
  required List<ContextFragment> fragments,
  required int budget,
  required String prompt,
  required TokenEstimator estimator,
  required int maxBeats,
}) {
  final selected = <ContextFragment>[];
  var used = estimator(prompt);
  var truncated = false;

  for (final f in fragments) {
    if (selected.length >= maxBeats) {
      truncated = true;
      break;
    }
    final text = _fragmentText(world, f);
    final cost = estimator(text);
    if (used + cost > budget) {
      truncated = true;
      continue;
    }
    selected.add(f);
    used += cost;
  }

  return (selected: selected, tokensUsed: used, truncated: truncated);
}

String _fragmentText(World world, ContextFragment f) {
  final (entity, valid) = world.getEntity(f.beat);
  if (!valid) return '';
  final text = entity.get<TextContent>();
  return text?.text ?? '';
}

/// System 3: Actors that hold [Agency] act.
///
/// Builds an [ActorGenerateRequest], registers an in-flight task, and
/// dispatches it to the [GenerationHandler] resolved via
/// [GenerationHandlerResource]. The handler performs the actual LLM call
/// (fire-and-forget) and sends back an [ActorGenerateResponse] on a later
/// tick.
///
/// This system is async-parallel: many actors can act concurrently.
/// Responses are processed by [processResponsesSystem] on a later tick.
///
/// Instead of removing [Agency] immediately, adds [AwaitingResponse] so
/// that the actor's state is preserved for retry on failure.
Future<void> actorActSystem(World world) async {
  final actorsWithAgency = world.query4<Actor, Agency, ActorModel, Situation>();
  final handlerResource = world.getResource<GenerationHandlerResource>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  for (final (entity, actor, _, model, situation) in actorsWithAgency) {
    final systemPrompt = entity.get<ActorSystemPrompt>();

    // Escalation: if this actor requested a stronger model, swap the model
    // binding for this request. The result folds back into the narrative
    // state via the normal response path.
    final escalate = entity.has<EscalationRequest>();
    final effectiveModel = escalate
        ? _resolveEscalatedModel(world, model)
        : model;

    final toolRegistry = situation.toolRegistryName != null
        ? world.getResource<ToolRegistryResource>().get(
            situation.toolRegistryName!,
          )
        : null;

    // The projected, budget-limited context beats — the cinematic cut.
    // The model sees ONLY what projection selected, never raw history.
    final contextFragments = <Object>[];
    for (final fragment in situation.contextFragments) {
      final beatEntity = world.getEntity(fragment.beat);
      if (!beatEntity.$2) continue;
      final beat = beatEntity.$1;
      final textContent = beat.get<TextContent>();
      if (textContent != null) {
        contextFragments.add('${fragment.type.name}:${textContent.text}');
      } else {
        contextFragments.add(fragment.type.name);
      }
    }
    // Green-screen absences are part of the cut.
    for (final absence in situation.explicitAbsences) {
      contextFragments.add('absence:$absence');
    }

    final taskId = TaskId.create();
    taskRegistry.register(taskId, TaskHandle());

    final request = ActorGenerateRequest(
      actorEntity: entity.entity,
      agentId: actor.agentId,
      modelId: effectiveModel.modelId,
      prompt: situation.prompt,
      systemPrompt: systemPrompt?.text ?? '',
      contextFragments: contextFragments,
      schema: situation.schema,
      toolRegistry: toolRegistry,
      task: situation.schema.isEmpty
          ? InferenceTask.text
          : InferenceTask.nativelyStructuredText,
      taskId: taskId,
    );

    // Add AwaitingResponse — preserves actor state for retry on failure.
    // Agency is consumed by processResponsesSystem after the response arrives.
    entity.insert(AwaitingResponse(taskId: taskId));

    // Publish the request to the event channel for observability/audit, then
    // fire-and-forget the handler. The handler sends ActorGenerateResponse
    // (and optionally ActorGenerateStreamEvent) back to the world's channels.
    world.events.writer<ActorGenerateRequest>().send(request);
    final handler = handlerResource.resolve(request);
    if (handler != null) {
      unawaited(handler.generate(world, request));
    }
  }
}

/// Resolve the escalated model for an actor.
///
/// Uses the [ModelRouterResource] to find a stronger model than the actor's
/// current binding. If none is configured, falls back to the actor's own
/// model (escalation is best-effort).
ActorModel _resolveEscalatedModel(World world, ActorModel current) {
  final router = world.getResource<ModelRouterResource>().router;
  // Prefer a model whose id is not the current one (a "bigger" binding).
  for (final m in router.models.values) {
    if (m.id != current.modelId) return ActorModel(modelId: m.id);
  }
  return current;
}

/// System 4a: Append streaming chunks to actors' [StreamingBeat]s.
///
/// Mechanical — no LLM calls. Reads [ActorGenerateStreamEvent]s and appends
/// the chunk to the target actor's partial buffer for live UI rendering.
void processStreamEventsSystem(World world) {
  final reader = world.events.reader<ActorGenerateStreamEvent>();
  final events = reader.drain();
  world.events.channel<ActorGenerateStreamEvent>().clear();

  for (final event in events) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;
    final (we, _) = entity;
    final streaming = we.get<StreamingBeat>() ?? StreamingBeat();
    streaming.chunks.add(event.chunk);
    we.insert(streaming);
  }
}

/// System 4: Process LLM responses from handlers.
///
/// Mechanical — no LLM calls, no tool execution. Reads
/// [ActorGenerateResponse] events, resolves the associated task, and stores
/// them as Beat entities.
///
/// For tool calls that were parsed by the handler (non-native backends),
/// sends [ToolCallEvent]s for the [toolExecutionSystem] to process.
/// For tool results that were already executed by the handler (Apple
/// Foundation native), stores them directly as Beats.
///
/// Consumes [Agency] + [AwaitingResponse] + [OpenDecision] after storing
/// the response. On failure (null response): creates a new [OpenDecision]
/// with an error note for retry.
void processResponsesSystem(World world) {
  final responseReader = world.events.reader<ActorGenerateResponse>();
  final toolCallWriter = world.events.writer<ToolCallEvent>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  final responses = responseReader.drain();
  world.events.channel<ActorGenerateResponse>().clear();

  for (final response in responses) {
    // Resolve the in-flight task — the host awaiting this actor's response
    // (via TaskRegistryResource) is resumed here.
    final taskId = response.taskId;
    if (taskId != null) {
      final handle = taskRegistry.take(taskId);
      if (handle != null && !handle.completer.isCompleted) {
        handle.completer.complete(response);
      }
    }

    final entity = world.getEntity(response.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;
    final memories = we.get<ActorRuntimeMemories>();
    if (memories == null) continue;

    // Store the model response as a Beat entity
    final responseBeat = world.reserveEmptyEntity().entity;
    final responseBeatEntity = world.getEntity(responseBeat).$1;
    responseBeatEntity.insert(
      TextContent(jsonEncode(response.structuralOutput)),
    );
    responseBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    responseBeatEntity.insert(BeatModality(BeatModalityEnum.text));
    memories.fragments.add(
      ContextFragment(
        type: ContextFragmentType.modelResponse,
        beat: responseBeat,
      ),
    );

    // Dispatch parsed tool calls as ToolCallEvents for the
    // ToolExecutionSystem to process. This is the ECS way —
    // tools are executed by a system, not by the handler.
    for (final call in response.toolCalls) {
      toolCallWriter.send(
        ToolCallEvent(actorEntity: response.actorEntity, call: call),
      );
    }

    // Store tool results that were already executed by the handler
    // (e.g., Apple Foundation native tool calls).
    for (final result in response.toolResults) {
      final toolBeat = world.reserveEmptyEntity().entity;
      final toolBeatEntity = world.getEntity(toolBeat).$1;
      toolBeatEntity.insert(
        TextContent('<result|${result.name}|${jsonEncode(result.output)}>'),
      );
      toolBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
      toolBeatEntity.insert(BeatModality(BeatModalityEnum.toolCall));
      memories.fragments.add(
        ContextFragment(type: ContextFragmentType.toolMessage, beat: toolBeat),
      );
    }

    // Consume Agency + AwaitingResponse + OpenDecision — actor responded.
    // If the response was null/empty, create a new OpenDecision for retry.
    if (response.structuralOutput.isEmpty && response.rawOutput.isEmpty) {
      we.insert(
        const OpenDecision(
          prompt:
              'Error: LLM returned empty response. Retry with tighter context.',
        ),
      );
    } else {
      // Remove the OpenDecision — it has been resolved
      we.remove<OpenDecision>();
    }
    we.remove<Agency>();
    we.remove<AwaitingResponse>();
    we.remove<EscalationRequest>();
  }
}

/// System 5: Execute tool calls dispatched as [ToolCallEvent]s.
///
/// Reads [ToolCallEvent]s from the event channel, executes the tools
/// via the [ToolRegistryResource], and sends [ToolResultEvent]s back.
///
/// When a [ToolCallEvent] carries a [taskId] (native tool call routed via
/// [WorldToolBridge]), the associated [TaskHandle] is resolved after
/// execution — resuming the suspended native generation.
void toolExecutionSystem(World world) {
  final toolCallReader = world.events.reader<ToolCallEvent>();
  final toolResultWriter = world.events.writer<ToolResultEvent>();
  final toolRegistryResource = world.getResource<ToolRegistryResource>();
  final taskRegistry = world.getResource<TaskRegistryResource>();

  final toolCalls = toolCallReader.drain();
  world.events.channel<ToolCallEvent>().clear();

  for (final event in toolCalls) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;
    final tools = we.get<ActorTools>();
    final toolRegistry = tools != null
        ? toolRegistryResource.get(tools.registryName)
        : null;

    if (toolRegistry == null) {
      final result = ToolExecutionResult(
        name: event.call.name.value,
        output: {'error': 'No tool registry'},
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      _resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    final toolDef = toolRegistry.get(event.call.name);
    if (toolDef == null) {
      final result = ToolExecutionResult(
        name: event.call.name.value,
        output: {'error': 'Unknown tool'},
      );
      toolResultWriter.send(
        ToolResultEvent(actorEntity: event.actorEntity, result: result),
      );
      _resolveToolTask(world, taskRegistry, event.taskId, result);
      continue;
    }

    // Execute the tool. Most tools complete synchronously, but
    // async tools are handled via .then() — the result is sent
    // as a ToolResultEvent when it arrives.
    unawaited(
      toolDef.execute(event.call.arguments).then((value) {
        final result = ToolExecutionResult(
          name: event.call.name.value,
          output: value,
        );
        toolResultWriter.send(
          ToolResultEvent(actorEntity: event.actorEntity, result: result),
        );
        _resolveToolTask(world, taskRegistry, event.taskId, result);
      }),
    );
  }
}

void _resolveToolTask(
  World world,
  TaskRegistryResource taskRegistry,
  TaskId? taskId,
  ToolExecutionResult result,
) {
  if (taskId == null) return;
  final handle = taskRegistry.take(taskId);
  if (handle != null && !handle.completer.isCompleted) {
    handle.completer.complete(result);
  }
}

/// System 6: Process tool results from [ToolResultEvent]s.
///
/// Reads [ToolResultEvent]s and stores them as Beat entities in the
/// actor's memory. This runs after [toolExecutionSystem] in the same
/// Mechanical schedule tick.
void processToolResultsSystem(World world) {
  final resultReader = world.events.reader<ToolResultEvent>();

  final results = resultReader.drain();
  world.events.channel<ToolResultEvent>().clear();

  for (final event in results) {
    final entity = world.getEntity(event.actorEntity);
    if (!entity.$2) continue;

    final (we, _) = entity;
    final memories = we.get<ActorRuntimeMemories>();
    if (memories == null) continue;

    final toolBeat = world.reserveEmptyEntity().entity;
    final toolBeatEntity = world.getEntity(toolBeat).$1;
    toolBeatEntity.insert(
      TextContent(
        '<result|${event.result.name}|${jsonEncode(event.result.output)}>',
      ),
    );
    toolBeatEntity.insert(BeatStatus(BeatStatusEnum.complete));
    toolBeatEntity.insert(BeatModality(BeatModalityEnum.toolCall));
    memories.fragments.add(
      ContextFragment(type: ContextFragmentType.toolMessage, beat: toolBeat),
    );
  }
}

// ─────────────────────────────────────────────
// Bounded memory via mechanical delegation (Phase 2)
// ─────────────────────────────────────────────

/// Mechanical system: compacts old raw memory into summaries — a graph
/// transformation over the actor's threads, with a cache fallback.
///
/// The harness, not the model, owns history, and memory lives *in* the
/// storyline (threads of beats), not in a parallel log. When a thread of the
/// actor has too many raw beats, the oldest
/// [MemoryCompactionPolicy.summaryEvery] beats are merged into a single
/// [MemorySummary] *node that stays in that thread* (via [BelongsToThread]);
/// the compacted beats are marked `archived` (off the projection path) but
/// remain queryable for history. The actor's [ActorRuntimeMemories.fragments]
/// cache is then re-derived from the thread graph.
///
/// When the actor has no thread links yet (legacy/cache-only usage), it falls
/// back to a fragment-list compaction so bounded context still holds.
void compactMemorySystem(World world) {
  final policy = world.getResource<MemoryCompactionPolicy>();

  final actors = world.query2<Actor, ActorRuntimeMemories>();
  for (final (entity, _, memories) in actors.toList()) {
    final ref = entity.get<ActorMemoryRef>();
    final hasThreads = ref != null && ref.threads.isNotEmpty;

    if (hasThreads) {
      _compactThreadMemory(world, entity, ref, memories, policy);
      // Source of truth is the graph — rebuild the cache from it.
      entity.insert(
        ActorRuntimeMemories(fragments: _threadFragments(world, entity)),
      );
    } else {
      _compactCacheMemory(world, entity, memories, policy);
    }
  }
}

/// Graph-native compaction: merge a thread's oldest raw beats into a single
/// in-thread summary node, mark the compacted beats archived.
void _compactThreadMemory(
  World world,
  WorldEntity entity,
  ActorMemoryRef ref,
  ActorRuntimeMemories memories,
  MemoryCompactionPolicy policy,
) {
  for (final thread in ref.threads) {
    final (t, valid) = world.getEntity(thread);
    if (!valid) continue;

    final beats =
        world
            .query2<BelongsToThread, BeatStatus>()
            .where((r) => r.$2.thread == thread)
            .map(
              (r) => (
                beat: r.$1.entity,
                seq: r.$1.get<BeatSequence>()?.value ?? 0,
                raw:
                    !r.$1.has<MemorySummary>() &&
                    r.$3.value != BeatStatusEnum.archived,
              ),
            )
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));

    final activeRaw = beats.where((b) => b.raw).toList();
    if (activeRaw.length <= policy.maxRawFragments) continue;

    final toCompact = activeRaw.take(policy.summaryEvery).toList();
    if (toCompact.isEmpty) continue;

    final summaryText = _summarizeFragments(
      world,
      toCompact.map((b) => b.beat).toList(),
      policy.summaryLength,
    );

    final summaryBeat = world.reserveEmptyEntity().entity;
    final se = world.getEntity(summaryBeat).$1;
    se.insert(TextContent(summaryText));
    se.insert(BeatStatus(BeatStatusEnum.complete));
    se.insert(BeatModality(BeatModalityEnum.observation));
    se.insert(MemorySummary(summaryText));
    se.insert(SummaryOwner(entity.entity));
    se.insert(BelongsToThread(thread));
    se.insert(BeatSequence(_nextThreadBeatSeq(world, thread)));

    // Archive the compacted beats (off the projection path, kept for history).
    for (final b in toCompact) {
      final (we, ok) = world.getEntity(b.beat);
      if (!ok) continue;
      final st = we.get<BeatStatus>();
      if (st != null) {
        st.value = BeatStatusEnum.archived;
      }
    }
  }
}

int _nextThreadBeatSeq(World world, Entity thread) {
  var max = 0;
  for (final (_, belongs, seq)
      in world.query2<BelongsToThread, BeatSequence>()) {
    if (belongs.thread != thread) continue;
    if (seq.value > max) max = seq.value;
  }
  return max + 1;
}

/// Cache-only fallback: compact a plain fragment list (no thread links yet).
void _compactCacheMemory(
  World world,
  WorldEntity entity,
  ActorRuntimeMemories memories,
  MemoryCompactionPolicy policy,
) {
  final fragments = memories.fragments;
  if (fragments.length <= policy.maxRawFragments) return;

  final raw = fragments
      .where((f) => f.type != ContextFragmentType.memorySummary)
      .toList();
  if (raw.length < policy.summaryEvery) return;

  final toCompact = raw.take(policy.summaryEvery).toList();
  final summaryText = _summarizeFragments(
    world,
    toCompact.map((f) => f.beat).toList(),
    policy.summaryLength,
  );

  final summaryBeat = world.reserveEmptyEntity().entity;
  final se = world.getEntity(summaryBeat).$1;
  se.insert(TextContent(summaryText));
  se.insert(BeatStatus(BeatStatusEnum.complete));
  se.insert(BeatModality(BeatModalityEnum.observation));
  se.insert(MemorySummary(summaryText));
  se.insert(SummaryOwner(entity.entity));

  final compactedIds = toCompact.map((f) => f.beat).toSet();
  memories.fragments = fragments
      .where((f) => !compactedIds.contains(f.beat))
      .toList();
  memories.fragments.insert(
    0,
    ContextFragment(type: ContextFragmentType.memorySummary, beat: summaryBeat),
  );
}

/// Deterministic, mechanical summarization: keep the head and tail of the
/// compacted fragments, joined with a separator. This is a lossy but bounded
/// compression — the full beats remain queryable in the world for later
/// reconstruction (the projection just no longer shows them raw).
String _summarizeFragments(World world, List<Entity> beats, int maxLength) {
  final parts = <String>[];
  for (final beat in beats) {
    final (entity, valid) = world.getEntity(beat);
    if (!valid) continue;
    final text = entity.get<TextContent>();
    if (text != null && text.text.isNotEmpty) {
      parts.add(text.text);
    }
  }
  if (parts.isEmpty) return '';

  final joined = parts.join(' | ');
  if (joined.length <= maxLength) return joined;

  // Keep the head and tail, drop the middle.
  final headLen = maxLength * 2 ~/ 3;
  final tailLen = maxLength ~/ 3;
  final head = joined.substring(0, headLen);
  final tail = joined.substring(joined.length - tailLen);
  return '$head … $tail';
}

// ─────────────────────────────────────────────
// Default generation handler
// ─────────────────────────────────────────────

/// Default handler that uses [ModelRouterResource] to resolve models
/// and call the inference client directly.
///
/// ## Backend-agnostic tool handling
///
/// All tool calls route through the world. The handler wraps the actor's
/// [ToolRegistry] in a [WorldToolBridge] before passing it to the model:
///
/// - **Apple Foundation (native)**: The model executes tools during
///   generation. Each call fires the bridge, which sends a [ToolCallEvent]
///   to the world and suspends until [toolExecutionSystem] resolves it.
/// - **Raw LLM backends**: The model emits tool tags in text; the handler
///   parses them into [toolCalls] for the world's [toolExecutionSystem].
///
/// The handler NEVER executes tools itself — that's the ECS layer's job.
class DefaultGenerationHandler implements GenerationHandler {
  DefaultGenerationHandler({ModelRouter? router}) : _router = router;

  ModelRouter? _router;

  ModelRouter? get router => _router;

  set router(ModelRouter value) {
    _router = value;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final router = _router;
    if (router == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
        taskId: request.taskId,
      );
    }

    // Resolve the model from the router's registered models
    final model = router.models[request.modelId] ?? Model(id: request.modelId);

    final runtime = await router.waitAndGetRuntimeModel(model);

    // Bridge tools through the world so native tool calls route through ECS.
    final bridgedRegistry = request.toolRegistry != null
        ? WorldToolBridge(
            world: world,
            actorEntity: request.actorEntity,
            source: request.toolRegistry!,
          ).buildRegistry()
        : null;

    final response = await runtime.generate(
      prompt: request.prompt,
      systemPrompt: request.systemPrompt,
      contextFragments: request.contextFragments,
      outputSchema: request.schema,
      toolRegistry: bridgedRegistry,
      task: request.task,
    );

    if (response == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
        taskId: request.taskId,
      );
    }

    // Tool calls. Prefer the structured calls parsed by the inference client
    // (native tool calling — OpenRouter, OpenAI, Apple Foundation). For raw/
    // legacy backends that emit `<call|...>` tags in rawOutput, fall back to
    // the tag parser. The client owns wire-format parsing; ecsly stays
    // structured + raw output.
    final toolCalls = response.toolCalls.isNotEmpty
        ? response.toolCalls
              .map(
                (c) => ToolCall(name: ToolName(c.name), arguments: c.arguments),
              )
              .toList()
        : parseToolCalls(response.rawOutput ?? '');

    // Convert InferenceResponse.toolResults to ToolExecutionResult objects.
    // For Apple Foundation (native), these are already executed results.
    final toolResults = response.toolResults
        .map((r) => ToolExecutionResult(name: r.name, output: r.output))
        .toList();

    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: response.output,
      rawOutput: response.rawOutput ?? '',
      toolCalls: toolCalls,
      toolResults: toolResults,
      taskId: request.taskId,
    );
  }
}

/// Parse tool calls from raw LLM output using tag-based parsing.
///
/// This is the default parser for raw LLM backends that don't have
/// native tool call APIs. For backends with native tool call support
/// (Apple Foundation, OpenAI, etc.), the [ModelRuntime] should return
/// already-parsed [ToolCall] objects and this function is not used.
List<ToolCall> parseToolCalls(String rawOutput) {
  final tags = ToolTagParser.parse(rawOutput);
  final calls = tags.where((t) => t.type == ToolTagType.call).toList();
  return calls
      .map(
        (tag) => ToolCall(
          name: ToolName(tag.toolName),
          arguments: tag.payload ?? {},
        ),
      )
      .toList();
}
