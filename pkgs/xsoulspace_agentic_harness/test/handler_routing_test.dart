// ignore_for_file: lines_longer_than_80_chars

/// Handler routing (LLM-free), driven through the PRODUCTION loop path.
///
/// B5 hard cut: the legacy manual-schedule tests
/// (`harness_headless_tools_test.dart`) drove schedules by hand with 50 ms
/// sleep/stepper crutches that masked the idle-race class
/// (see `run_until_idle_tool_race_test.dart` for the incident). The two
/// unique coverage pieces — per-agent handler routing and runtime model
/// swap — were ported here onto `HarnessLoop.runUntilIdle`; the redundant
/// read/write/list_dir world-plumbing tests already live in
/// `fs_tools_test.dart` + the tool-race regression file.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show openFreshDecision;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// A [GenerationHandler] that records which agent/model it served.
class _TaggedHandler implements GenerationHandler {
  _TaggedHandler(this.tag);

  final String tag;
  final List<AgentId> handled = [];
  final List<ModelId> served = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    handled.add(request.agentId);
    served.add(request.modelId);
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'from $tag'},
      rawOutput: 'from $tag',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test('routes each agent to its own GenerationHandler (runUntilIdle path)',
      () async {
    final world = await buildTestWorld();

    // Two handlers — simulates Apple Foundation + OpenRouter (or any two
    // backends). Each is registered per-agent.
    final appleHandler = _TaggedHandler('apple');
    final openRouterHandler = _TaggedHandler('openrouter');
    world
        .getResource<GenerationHandlerResource>()
      ..registerForAgent(const AgentId('agent-apple'), appleHandler)
      ..registerForAgent(const AgentId('agent-openrouter'), openRouterHandler);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    world.spawnComponents([
      Actor(agentId: const AgentId('agent-apple')),
      ActorModel(modelId: ModelId.create()),
      PresentInScene(sceneEntity: scene),
      OpenDecision(prompt: 'Apple decision'),
    ]);
    world.spawnComponents([
      Actor(agentId: const AgentId('agent-openrouter')),
      ActorModel(modelId: ModelId.create()),
      PresentInScene(sceneEntity: scene),
      OpenDecision(prompt: 'OpenRouter decision'),
    ]);
    world.flush();

    // The production path: run until idle — no manual schedules, no sleeps.
    await HarnessLoop(world: world).runUntilIdle();

    // Each handler handled exactly its own agent.
    expect(appleHandler.handled, [const AgentId('agent-apple')]);
    expect(openRouterHandler.handled, [const AgentId('agent-openrouter')]);

    // Each actor's response was stored as an indexed beat from its own
    // handler.
    final index = world.getResource<FacetIndex>();
    bool beatMentions(Iterable<Entity> beats, String needle) => beats.any(
      (b) =>
          world.getEntity(b).$1.get<TextContent>()?.text.contains(needle) ??
          false,
    );
    expect(
      beatMentions(index.beatsFor(const ['apple']), 'apple'),
      isTrue,
    );
    expect(
      beatMentions(index.beatsFor(const ['openrouter']), 'openrouter'),
      isTrue,
    );

    expectIdle(world);
  });

  test('swaps inference backend at runtime by changing ActorModel',
      () async {
    final world = await buildTestWorld();
    // Two handlers registered by MODEL id — simulates Apple Foundation and
    // OpenRouter both being first-class models in the router.
    final appleModelId = const ModelId('model-apple');
    final openRouterModelId = const ModelId('model-openrouter');
    final appleHandler = _TaggedHandler('apple');
    final openRouterHandler = _TaggedHandler('openrouter');
    world
        .getResource<GenerationHandlerResource>()
      ..registerForModel(appleModelId, appleHandler)
      ..registerForModel(openRouterModelId, openRouterHandler);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: const AgentId('agent-apple')),
      ActorModel(modelId: appleModelId),
      PresentInScene(sceneEntity: scene),
      OpenDecision(prompt: 'First decision'),
    ]);
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();
    expect(appleHandler.served, [appleModelId]);
    expect(openRouterHandler.served, isEmpty);

    // Swap the actor's model at runtime, then open a fresh decision (the
    // host-injected retry path — openFreshDecision resets round budgets).
    world.upsertComponent(actor, ActorModel(modelId: openRouterModelId));
    openFreshDecision(world, actor, prompt: 'Second decision');

    await HarnessLoop(world: world).runUntilIdle();

    expect(appleHandler.served, [appleModelId]);
    expect(openRouterHandler.served, [openRouterModelId]);

    expectIdle(world);
  });
}
