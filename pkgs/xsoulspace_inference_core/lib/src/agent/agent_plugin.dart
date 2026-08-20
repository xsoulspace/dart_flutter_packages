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
class OpenDecision implements Component {
  const OpenDecision({this.schema = SchemaBundle.empty, this.prompt = ''});
  final SchemaBundle schema;
  final String prompt;
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
/// Contains only the props in frame, co-present actors, and the local question.
/// Built by [projectSituationSystem] and consumed by [actorActSystem].
class Situation implements Component {
  Situation({
    this.prompt = '',
    this.schema = SchemaBundle.empty,
    this.inFramePropIds = const [],
    this.coPresentActorIds = const [],
  });
  String prompt;
  SchemaBundle schema;
  List<String> inFramePropIds;
  List<AgentId> coPresentActorIds;
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
      ..registerObjectComponent<Agency>()
      ..registerObjectComponent<AwaitingResponse>()
      ..registerObjectComponent<OpenDecision>()
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
      ..registerObjectComponent<ObservationData>();

    // Resources
    world
      ..upsertResource(TaskRegistryResource())
      ..upsertResource(GenerationHandlerResource());

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
void grantAgencySystem(World world) {
  final actorsWithDecisions = world.query2<Actor, OpenDecision>();

  for (final (entity, _, _) in actorsWithDecisions) {
    if (entity.has<Agency>()) continue;
    if (entity.has<AwaitingResponse>()) continue;
    entity.insert(const Agency());
  }
}

/// System 2: Build a minimal [Situation] for each actor with [Agency].
///
/// Projection is ruthlessly minimal and cinematic — only props in frame,
/// co-present actors, and the local question. Context windows stay tiny.
void projectSituationSystem(World world) {
  final actorsWithAgency = world.query3<Actor, Agency, ActorRuntimeMemories>();

  // Materialize the query results before mutating, since entity.insert()
  // changes archetypes and can invalidate lazy iterators.
  for (final (entity, actor, _, _) in actorsWithAgency.toList()) {
    final situation = _buildSituation(
      world: world,
      entity: entity,
      actor: actor,
    );
    entity.insert(situation);
  }
}

Situation _buildSituation({
  required World world,
  required WorldEntity entity,
  required Actor actor,
}) {
  // Find the current scene
  WorldEntity? sceneEntity;
  for (final (sceneEnt, _, _) in world.query2<Scene, SceneFrame>()) {
    sceneEntity = sceneEnt;
    break;
  }
  if (sceneEntity == null) return Situation();

  // Find co-present actors (same scene, excluding self)
  final coPresent = <AgentId>[];
  for (final (_, present, otherActor)
      in world.query2<PresentInScene, Actor>()) {
    if (present.sceneEntity == sceneEntity.entity &&
        otherActor.agentId != actor.agentId) {
      coPresent.add(otherActor.agentId);
    }
  }

  // Find props in frame
  final inFrameProps = <String>[];
  for (final (_, present, prop) in world.query2<PresentProp, Prop>()) {
    if (present.sceneEntity == sceneEntity.entity) {
      inFrameProps.add(prop.name);
    }
  }

  // Build the prompt from the open decision
  final decision = entity.get<OpenDecision>();
  final prompt = decision?.prompt ?? '';

  return Situation(
    prompt: prompt,
    schema: decision?.schema ?? SchemaBundle.empty,
    inFramePropIds: inFrameProps,
    coPresentActorIds: coPresent,
  );
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
    final memories = entity.get<ActorRuntimeMemories>();
    final systemPrompt = entity.get<ActorSystemPrompt>();
    final tools = entity.get<ActorTools>();

    final toolRegistry = tools != null
        ? world.getResource<ToolRegistryResource>().get(tools.registryName)
        : null;

    // Build context fragments from Beat entities referenced by ContextFragment.
    final contextFragments = <Object>[];
    if (memories != null) {
      for (final fragment in memories.fragments) {
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
    }

    final taskId = TaskId.create();
    taskRegistry.register(taskId, TaskHandle());

    final request = ActorGenerateRequest(
      actorEntity: entity.entity,
      agentId: actor.agentId,
      modelId: model.modelId,
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

    // Parse tool calls from raw output using the tag-based parser.
    // For Apple Foundation (native), the ModelRuntime handles tools
    // during generation — rawOutput won't contain tool tags, so
    // toolCalls will be empty and toolResults will contain the results.
    // For raw LLM backends, parse tool calls for the ECS
    // ToolExecutionSystem to execute.
    final toolCalls = parseToolCalls(response.rawOutput ?? '');

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
