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
class ActorRuntimeMemories implements Component {
  ActorRuntimeMemories({List<ContextFragment>? fragments})
    : fragments = fragments ?? <ContextFragment>[];

  List<ContextFragment> fragments;
}

/// A single context fragment in an actor's memory.
class ContextFragment {
  const ContextFragment({required this.type, required this.value});
  final ContextFragmentType type;
  final String value;
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
/// [toolCalls] contains parsed tool call tags if the model emitted any.
///
/// [rawOutput] - shows output as it is come from llm
class ActorGenerateResponse implements EcsEvent {
  const ActorGenerateResponse({
    required this.actorEntity,
    required this.structuralOutput,
    required this.rawOutput,
    this.toolCalls = const [],
  });

  final Entity actorEntity;
  final Map<String, dynamic> structuralOutput;
  final String rawOutput;
  final List<ToolCall> toolCalls;
}

/// A parsed tool call from an LLM response.
class ToolCall {
  const ToolCall({required this.name, required this.arguments});
  final ToolName name;
  final Map<String, dynamic> arguments;
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

    // Schedules — the cinematic multi-actor loop
    //
    // 1. AgencyGrant: grant Agency to actors with OpenDecision
    // 2. Project: build minimal Situations for actors with Agency
    // 3. ActorAct: async — send LLM requests, external handler responds
    // 4. ProcessResponses: handle LLM responses, queue tool calls
    // 5. Mechanical: score/prune threads, execute tools
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
      ..add(scoreThreadsSystem, name: 'scoreThreads')
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

    final contextFragments =
        memories?.fragments.map((f) => '${f.type.name}:${f.value}').toList() ??
        [];

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
/// Mechanical — no LLM calls. Reads [ActorGenerateResponse] events,
/// stores the output as a context fragment, and executes tool calls
/// synchronously (tools are typically fast; only LLM calls are truly async).
///
/// Consumes [Agency] + [AwaitingResponse] after storing the response.
/// On failure (null response): creates a new [OpenDecision] with an error note.
void processResponsesSystem(World world) {
  final responseReader = world.events.reader<ActorGenerateResponse>();
  final toolRegistryResource = world.getResource<ToolRegistryResource>();

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

    // Store the model response
    memories.fragments.add(
      ContextFragment(
        type: ContextFragmentType.modelResponse,
        value: jsonEncode(response.structuralOutput),
      ),
    );

    // Resolve the actor's tool registry by name (not by tool name)
    final tools = we.get<ActorTools>();
    final toolRegistry = tools != null
        ? toolRegistryResource.get(tools.registryName)
        : null;

    // Execute tool calls synchronously (MVP decision — tools are fast).
    // Slow async tool calls would be deferred to the result queue.
    for (final call in response.toolCalls) {
      if (toolRegistry == null) {
        memories.fragments.add(
          ContextFragment(
            type: ContextFragmentType.toolMessage,
            value: '<result|${call.name.value}|{"error":"No tool registry"}>',
          ),
        );
        continue;
      }

      final toolDef = toolRegistry.get(call.name);
      if (toolDef == null) {
        memories.fragments.add(
          ContextFragment(
            type: ContextFragmentType.toolMessage,
            value: '<result|${call.name.value}|{"error":"Unknown tool"}>',
          ),
        );
        continue;
      }

      // Synchronous execution — await the Future directly.
      // ToolDef.execute returns Future<dynamic>, but most tools complete
      // synchronously. For truly async tools, the result is processed
      // via .then() with unawaited to avoid blocking the ECS loop.
      // Slow async tool calls would be deferred to the result queue.
      unawaited(
        toolDef.execute(call.arguments).then((value) {
          memories.fragments.add(
            ContextFragment(
              type: ContextFragmentType.toolMessage,
              value: '<result|${call.name.value}|${jsonEncode(value)}>',
            ),
          );
        }),
      );
    }

    // Consume Agency + AwaitingResponse + OpenDecision — the actor has responded.
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
    // For Apple Foundation (native), the ModelRuntime returns already-parsed
    // ToolCall objects, so this parsing is backend-specific.
    final toolCalls = parseToolCalls(response.rawOutput ?? '');

    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: response.output,
      rawOutput: response.rawOutput ?? '',
      toolCalls: toolCalls,
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
