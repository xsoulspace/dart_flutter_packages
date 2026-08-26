/// Facade for wiring an agent world: spawn the scene, actors, and threads.
///
/// Extracted from [ScenarioRunner]'s setup ritual so hosts (CLI, Flutter,
/// tests) get the same one-call bootstrap instead of duplicating the
/// Scene → actors → threads → flush choreography.
///
/// ## Recipes
///
/// **Open a decision for an actor** (the only way a model is invoked —
/// agency is granted only when real work exists):
///
/// ```dart
/// final actor = setup.spawnActors([ActorSpec(name: 'a', systemPrompt: '…')], scene).single;
/// world.upsertComponent(actor.entity, OpenDecision(prompt: '…'));
/// world.flush();
/// ```
///
/// **Register tools** on the registry actors are bound to (see
/// `example/lib/headless/02_tool_routing.dart`):
///
/// ```dart
/// setup.registerTools([ToolDef.encode(name: ToolName('echo'), ...)]);
/// ```
library;

import 'package:ecsly/ecsly.dart';

import 'data_models/data_models.dart';
import 'model_router.dart';
import 'narrative/narrative.dart';
import 'resources/resources.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A declarative actor description for [AgentWorldSetup.spawnActors].
class ActorSpec {
  ActorSpec({required this.name, required this.systemPrompt});

  /// Human-readable name (used by metrics/reporting).
  final String name;

  /// The actor's system prompt / identity.
  final String systemPrompt;
}

/// One spawned actor: entity handle plus its thread and display name.
class SpawnedActor {
  SpawnedActor({required this.entity, required this.name, Entity? thread})
    : thread = thread ?? Entity.create(0);
  final Entity entity;

  /// The actor's first thread (projection ray-traces it). Assigned during
  /// [AgentWorldSetup.spawnActors].
  Entity thread;
  final String name;
}

/// Spawns scene + actors + threads into an [AgentPlugin]-installed world.
class AgentWorldSetup {
  AgentWorldSetup({required this.world});

  final World world;

  /// Spawn the singleton [Scene] and return its entity.
  Entity spawnScene() {
    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    world.flush();
    return scene;
  }

  /// Spawn [specs] as actors in [scene], each with its own thread bound to
  /// the `'default'` tool registry.
  List<SpawnedActor> spawnActors(
    List<ActorSpec> specs,
    Entity scene, {
    String registryName = 'default',
  }) {
    final spawned = <SpawnedActor>[];
    for (final spec in specs) {
      final e = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorSystemPrompt(text: spec.systemPrompt),
        ActorThreads(threads: []),
        ActorTools(registryName: registryName),
        PresentInScene(sceneEntity: scene),
      ]);
      spawned.add(SpawnedActor(entity: e, name: spec.name));
    }
    world.flush();

    // Give each actor a thread so projection can ray-trace its own beats.
    for (final actor in spawned) {
      final thread = spawnThread(world, actor.entity, scene);
      world.upsertComponent(actor.entity, ActorThreads(threads: [thread]));
      actor.thread = thread;
    }
    world.flush();
    return spawned;
  }

  /// Register [tools] under [registryName] (creating the registry if needed).
  void registerTools(
    Iterable<ToolDef> tools, {
    String registryName = 'default',
  }) {
    final resource = world.getResource<ToolRegistryResource>();
    final registry = resource.get(registryName) ?? ToolRegistry();
    tools.forEach(registry.register);
    resource.register(registryName, registry);
    world.flush();
  }
}
