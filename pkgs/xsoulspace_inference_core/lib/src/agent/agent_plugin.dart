import 'dart:async';
import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';
import 'package:ecsly_async_parallel/ecsly_async_parallel.dart';

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
/// Consumed by [actorActSystem] and removed after the actor acts.
class Agency implements Component {
  const Agency();
}

/// Tag component: this actor has dispatched an LLM request and is waiting
/// for a response.
///
/// Added by [actorActSystem] when the request is sent. Consumed by
/// [processResponsesSystem] after the response is processed.
/// Prevents re-granting Agency until the response arrives.
class AwaitingResponse implements Component {
  const AwaitingResponse();
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
// Events
// ─────────────────────────────────────────────

/// Request from an ECS system to generate LLM output for an actor.
///
/// Sent by [actorActSystem] to an external handler (e.g., a Flutter
/// integration or isolate) that performs the actual LLM call.
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
}

/// Response from the LLM handler back to the ECS world.
///
/// The external handler sends this after completing the generation.
/// [toolCalls] contains parsed tool calls if the model emitted any.
/// [toolResults] contains results of tool calls that were already
/// executed by the handler (e.g., Apple Foundation native tool calls).
///
/// ## Backend-specific tool handling
///
/// - **Apple Foundation (native)**: Tools are called during generation
///   by the ModelRuntime. The handler receives the final result with
///   tool results already resolved in [toolResults].
/// - **OpenAI/OpenRouter/DeepSeek**: The handler parses tool calls from
///   the response into [toolCalls]. These are sent as `ToolCallEvent`s
///   for the ECS `ToolExecutionSystem` to process.
/// - **Raw LLM**: Same as above — parse from text into [toolCalls].
///
/// The ECS layer processes [toolCalls] via `ToolExecutionSystem` and
/// stores [toolResults] as Beats.
///
/// [rawOutput] - shows output as it is come from llm
class ActorGenerateResponse implements EcsEvent {
  const ActorGenerateResponse({
    required this.actorEntity,
    required this.structuralOutput,
    required this.rawOutput,
    this.toolCalls = const [],
    this.toolResults = const [],
  });

  final Entity actorEntity;
  final Map<String, dynamic> structuralOutput;
  final String rawOutput;
  final List<ToolCall> toolCalls;
  final List<ToolExecutionResult> toolResults;
}

/// A parsed tool call from an LLM response.
///
/// Sent by the handler as a `ToolCallEvent` for the ECS
/// `ToolExecutionSystem` to process.
class ToolCall {
  const ToolCall({required this.name, required this.arguments});
  final ToolName name;
  final Map<String, dynamic> arguments;
}

/// Result of a tool call execution.
///
/// Sent by the `ToolExecutionSystem` as a `ToolResultEvent`
/// for `processToolResultsSystem` to store as a Beat.
class ToolExecutionResult {
  const ToolExecutionResult({required this.name, required this.output});
  final String name;
  final dynamic output;
}

/// Event: a tool call that needs to be executed by the ECS world.
///
/// Sent by the handler (for parsed tool calls) or by
/// `processResponsesSystem` (for tool calls that need execution).
/// Processed by `ToolExecutionSystem` in the Mechanical schedule.
class ToolCallEvent implements EcsEvent {
  const ToolCallEvent({required this.actorEntity, required this.call});
  final Entity actorEntity;
  final ToolCall call;
}

/// Event: a tool call result that has been executed.
///
/// Sent by `ToolExecutionSystem` after executing a `ToolCallEvent`.
/// Consumed by `processToolResultsSystem` to store as a Beat.
class ToolResultEvent implements EcsEvent {
  const ToolResultEvent({required this.actorEntity, required this.result});
  final Entity actorEntity;
  final ToolExecutionResult result;
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

    // Event channels for async LLM I/O
    world.events.register<ActorGenerateRequest>();
    world.events.register<ActorGenerateResponse>();
    world.events.register<ToolCallEvent>();
    world.events.register<ToolResultEvent>();

    // Schedules — the cinematic multi-actor loop
    //
    // 1. AgencyGrant: grant Agency to actors with OpenDecision
    // 2. Project: build minimal Situations for actors with Agency
    // 3. ActorAct: async — send LLM requests, external handler responds
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
      ..add(processResponsesSystem, name: 'processResponses')
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
  // Query: Actor + OpenDecision, then check for Agency/AwaitingResponse manually
  // (ecsly's query2 requires both components; we filter via has<T>)
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
/// For LLM actors: send [ActorGenerateRequest] to the event channel.
/// The actual LLM call is performed by an external handler (Flutter isolate,
/// CLI, etc.) which sends back [ActorGenerateResponse].
///
/// This system is async-parallel: many actors can act concurrently.
/// Responses are processed by [processResponsesSystem] on a later tick.
///
/// Instead of removing [Agency] immediately, adds [AwaitingResponse] so
/// that the actor's state is preserved for retry on failure.
Future<void> actorActSystem(World world) async {
  final requestWriter = world.events.writer<ActorGenerateRequest>();
  final actorsWithAgency = world.query4<Actor, Agency, ActorModel, Situation>();

  // Mark the actorAct job as in-flight so HarnessLoop.canSleep() knows
  // there is pending async work (LLM calls dispatched to the handler).
  final policy = world.getResource<ScheduleExecutionPolicyResource>();
  final queue = world.getResource<ScheduleJobResultQueueResource>();
  queue.beginInFlight(jobKey: 'actorAct', frameId: policy.frameId);

  for (final (entity, actor, _, model, situation) in actorsWithAgency) {
    final memories = entity.get<ActorRuntimeMemories>();
    final systemPrompt = entity.get<ActorSystemPrompt>();
    final tools = entity.get<ActorTools>();

    final toolRegistry = tools != null
        ? world.getResource<ToolRegistryResource>().get(tools.registryName)
        : null;

    // Build context fragments from Beat entities referenced by ContextFragment.
    // Each Beat's content is read from its modality-specific components.
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
    );

    requestWriter.send(request);

    // Add AwaitingResponse — preserves actor state for retry on failure.
    // Agency is consumed by processResponsesSystem after the response arrives.
    entity.insert(const AwaitingResponse());
  }

  // Yield to let the event loop process requests sent to the channel.
  // The external handler will send ActorGenerateResponse events back,
  // which are processed by processResponsesSystem on a later tick.
  await Future.delayed(Duration.zero);
}

/// System 4: Process LLM responses from the external handler.
///
/// Mechanical — no LLM calls, no tool execution. Reads
/// [ActorGenerateResponse] events and stores them as Beat entities.
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

  // Drain and clear the response channel so events don't persist across frames.
  final responses = responseReader.drain();
  world.events.channel<ActorGenerateResponse>().clear();

  // Complete the in-flight marker for this frame — LLM responses have arrived
  // and are being processed. Also clean up stale markers from previous frames.
  if (world.resources.has<ScheduleJobResultQueueResource>()) {
    final policy = world.getResource<ScheduleExecutionPolicyResource>();
    final queue = world.getResource<ScheduleJobResultQueueResource>();
    queue.completeInFlight(
      ScheduleJobResultEnvelope<Object>(
        jobKey: 'actorAct',
        frameId: policy.frameId,
        results: [],
      ),
    );
    queue.dropStaleResults(minFrameId: policy.frameId);
  }

  for (final response in responses) {
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
/// This is the ECS-native way to handle tool execution — tools are
/// executed by a system, not by the handler. The handler only parses
/// tool calls from LLM output; execution happens here.
void toolExecutionSystem(World world) {
  final toolCallReader = world.events.reader<ToolCallEvent>();
  final toolResultWriter = world.events.writer<ToolResultEvent>();
  final toolRegistryResource = world.getResource<ToolRegistryResource>();

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
      toolResultWriter.send(
        ToolResultEvent(
          actorEntity: event.actorEntity,
          result: ToolExecutionResult(
            name: event.call.name.value,
            output: {'error': 'No tool registry'},
          ),
        ),
      );
      continue;
    }

    final toolDef = toolRegistry.get(event.call.name);
    if (toolDef == null) {
      toolResultWriter.send(
        ToolResultEvent(
          actorEntity: event.actorEntity,
          result: ToolExecutionResult(
            name: event.call.name.value,
            output: {'error': 'Unknown tool'},
          ),
        ),
      );
      continue;
    }

    // Execute the tool. Most tools complete synchronously, but
    // async tools are handled via .then() — the result is sent
    // as a ToolResultEvent when it arrives.
    unawaited(
      toolDef.execute(event.call.arguments).then((value) {
        toolResultWriter.send(
          ToolResultEvent(
            actorEntity: event.actorEntity,
            result: ToolExecutionResult(
              name: event.call.name.value,
              output: value,
            ),
          ),
        );
      }),
    );
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
// External handler interface
// ─────────────────────────────────────────────

/// External handler that processes [ActorGenerateRequest] events
/// and sends back [ActorGenerateResponse] events.
///
/// This is the bridge between the ECS world and the actual LLM runtime.
/// Implementations live outside the core (e.g., in a Flutter isolate or CLI).
///
/// ## Polling pattern (not subscription)
///
/// The `EventChannel` uses ring-buffer snapshot semantics — `forEach`
/// creates a snapshot at call time and cannot see events sent later.
/// Therefore, the handler must be polled via [processPending] on each tick
/// of the [HarnessLoop], which drains the request channel and sends
/// responses. This avoids modifying ecsly's `EventChannel` and keeps the
/// handler lifecycle simple: the host application calls
/// `handler.processPending(world)` on each loop tick.
abstract class ActorGenerateHandler {
  /// Process a single generation request and return the response.
  Future<ActorGenerateResponse> handle(ActorGenerateRequest request);

  /// Process all pending requests in the world's event channel.
  ///
  /// This is the polling entry point — called by [HarnessLoop] on each tick.
  /// It drains the request channel, calls [handle] for each request, and
  /// sends responses back via the response channel.
  ///
  /// Implementations may override this for custom batching or concurrency,
  /// but the default implementation processes requests sequentially.
  Future<void> processPending(World world) async {
    final reader = world.events.reader<ActorGenerateRequest>();
    final writer = world.events.writer<ActorGenerateResponse>();

    final requests = reader.drain();
    for (final request in requests) {
      final response = await handle(request);
      writer.send(response);
    }
  }

  /// Register this handler with the world.
  ///
  /// Deprecated: Use [processPending] on each tick instead.
  /// The old `forEach` subscription pattern is broken because
  /// `EventChannel.forEach` creates a snapshot at call time and cannot
  /// see events sent after registration.
  @Deprecated('Use processPending(world) on each tick instead.')
  void register(World world) {
    // No-op — the handler is polled via processPending instead.
  }
}

/// Default handler that uses [ModelRouterResource] to resolve models
/// and call the inference client directly.
///
/// ## Backend-specific tool handling
///
/// - **Apple Foundation (native)**: The `ModelRuntime.generate()` handles
///   tool calls during generation. Tools are passed via `toolRegistry`
///   and executed natively. The handler receives the final result with
///   tool results already resolved in `response.toolResults`.
/// - **Raw LLM backends**: The handler parses tool calls from `rawOutput`
///   using `parseToolCalls()` and returns them in `toolCalls`. The ECS
///   `toolExecutionSystem` then executes them.
///
/// The handler NEVER executes tools itself — that's the ECS layer's job.
/// The handler only parses tool calls from LLM output (for non-native backends).
class DefaultActorGenerateHandler extends ActorGenerateHandler {
  /// The world must have [ModelRouterResource] registered.
  @override
  Future<ActorGenerateResponse> handle(ActorGenerateRequest request) async {
    final router = _router;
    if (router == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
      );
    }

    // Resolve the model from the router's registered models
    final model = router.models[request.modelId] ?? Model(id: request.modelId);

    final runtime = await router.waitAndGetRuntimeModel(model);

    final response = await runtime.generate(
      prompt: request.prompt,
      systemPrompt: request.systemPrompt,
      contextFragments: request.contextFragments,
      outputSchema: request.schema,
      toolRegistry: request.toolRegistry,
      task: request.task,
    );

    if (response == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
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
    );
  }

  ModelRouter? _router;

  ModelRouter? get router => _router;

  set router(ModelRouter value) {
    _router = value;
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
