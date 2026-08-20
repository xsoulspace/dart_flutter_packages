import 'dart:async';
import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';

import '../models/inference_models.dart';
import 'agent.dart';

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

/// A thread is an alternative / exploration path.
///
/// Threads are scoreable, prunable, and mergeable.
class Thread implements Component {
  const Thread({this.parentThreadId});
  final Entity? parentThreadId;
}

/// Score for a [Thread]. Higher is better.
class ThreadScore implements Component {
  ThreadScore({this.value = 0.0});
  double value;
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
    world.components
      ..registerObjectComponent<Actor>()
      ..registerObjectComponent<ActorModel>()
      ..registerObjectComponent<ActorSystemPrompt>()
      ..registerObjectComponent<ActorTools>()
      ..registerObjectComponent<ActorRuntimeMemories>()
      ..registerObjectComponent<Agency>()
      ..registerObjectComponent<OpenDecision>()
      ..registerObjectComponent<Scene>()
      ..registerObjectComponent<SceneFrame>()
      ..registerObjectComponent<PresentInScene>()
      ..registerObjectComponent<PresentProp>()
      ..registerObjectComponent<Prop>()
      ..registerObjectComponent<Situation>()
      ..registerObjectComponent<Thread>()
      ..registerObjectComponent<ThreadScore>()
      ..registerObjectComponent<Goal>();

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
      ..then(flushAllSystem, name: 'flushAfterMechanical');
  }

  @override
  String get name => 'agent-plugin';
}

// ─────────────────────────────────────────────
// Systems
// ─────────────────────────────────────────────

/// System 1: Grant agency to actors that have an [OpenDecision].
///
/// For each Actor entity with [OpenDecision] but without [Agency],
/// add the [Agency] tag. This is the explicit agency-granting step —
/// actors never assume agency; systems grant it.
void grantAgencySystem(World world) {
  // Query: Actor + OpenDecision, then check for Agency manually
  // (ecsly's query2 requires both components; we filter Agency via has<T>)
  final actorsWithDecisions = world.query2<Actor, OpenDecision>();

  for (final (entity, _, _) in actorsWithDecisions) {
    if (entity.has<Agency>()) continue;
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
Future<void> actorActSystem(World world) async {
  final requestWriter = world.events.writer<ActorGenerateRequest>();
  final actorsWithAgency = world.query4<Actor, Agency, ActorModel, Situation>();

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

    // Remove Agency — the actor has acted; it will be re-granted if needed
    entity.remove<Agency>();
  }

  // Yield to let the event loop process requests sent to the channel.
  // The external handler will send ActorGenerateResponse events back,
  // which are processed by processResponsesSystem on a later tick.
  await Future.delayed(Duration.zero);
}

/// System 4: Process LLM responses from the external handler.
///
/// Mechanical — no LLM calls. Reads [ActorGenerateResponse] events,
/// stores the output as a context fragment, and queues tool calls
/// for execution.
void processResponsesSystem(World world) {
  final responseReader = world.events.reader<ActorGenerateResponse>();
  final toolRegistryResource = world.getResource<ToolRegistryResource>();

  // Drain and clear the response channel so events don't persist across frames.
  final responses = responseReader.drain();
  world.events.channel<ActorGenerateResponse>().clear();

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

    // Execute tool calls (ToolDef.execute always returns Future<dynamic>)
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
  }
}

/// System 5: Score threads for pruning.
///
/// Mechanical — no LLM calls. Scores are based on heuristics.
void scoreThreadsSystem(World world) {
  final threads = world.query2<Thread, ThreadScore>();
  for (final (_, _, score) in threads) {
    // Placeholder: score based on fragment count
    score.value = 0.5;
  }
}

/// System 6: Prune low-scoring threads.
///
/// Mechanical — no LLM calls.
void pruneThreadsSystem(World world) {
  final threads = world.query2<Thread, ThreadScore>();
  // Materialize before despawning to avoid iterator invalidation.
  for (final (entity, _, score) in threads.toList()) {
    if (score.value < 0.1) {
      entity.despawn();
    }
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
abstract class ActorGenerateHandler {
  /// Process a single generation request and return the response.
  Future<ActorGenerateResponse> handle(ActorGenerateRequest request);

  /// Register this handler with the world's event channels.
  ///
  /// Call this once after the plugin is installed. The handler will
  /// listen for [ActorGenerateRequest] events and send responses.
  void register(World world) {
    // Listen for requests and process them
    // TODO: add listen method for EventChannel or onchange or stream kind
    // so we could subscribe to changes
    world.events.reader<ActorGenerateRequest>().forEach((request) {
      unawaited(
        handle(request).then((response) {
          world.events.writer<ActorGenerateResponse>().send(response);
        }),
      );
    });
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

    // Parse tool calls from raw output
    final toolCalls = _parseToolCalls(response.rawOutput ?? '');

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

List<ToolCall> _parseToolCalls(String rawOutput) {
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
