// ignore_for_file: lines_longer_than_80_chars

/// Shared support for agent-harness tests.
///
/// Centralizes the mock LLM handler and world/scene/actor builders so each
/// focused test file stays small and asserts one thing instead of repeating
/// setup machinery. Import this surfaced names only —
/// `agent_harness_support.dart` has no `main()`, so it never runs as a test.
library;

import 'dart:async';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A mock handler that simulates an LLM without requiring a real backend.
///
/// Returns a configurable [responseText] and optionally [toolCalls]. The
/// handler sends responses back to the world's event channel, mirroring how
/// a real isolate handler would consume the event channel.
class MockGenerationHandler implements GenerationHandler {
  MockGenerationHandler({
    required this.responseText,
    this.toolCalls = const [],
    this.responseOutput,
    this.delay = Duration.zero,
  });

  final String responseText;
  final List<ToolCall> toolCalls;
  final Map<String, dynamic>? responseOutput;
  final Duration delay;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    final output = responseOutput ?? {'text': responseText};
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: output,
      rawOutput: responseText,
      toolCalls: toolCalls,
      taskId: request.taskId,
    );

    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Helper to build a minimal world with the agent plugin and resources.
Future<World> buildTestWorld({
  ModelRouter? router,
  ToolRegistryResource? toolRegistryResource,
  GenerationHandler? handler,
}) async {
  final world = World()..addPlugin(AgentPlugin());

  world
    ..upsertResource(ModelRouterResource(router ?? ModelRouter()))
    ..upsertResource(toolRegistryResource ?? ToolRegistryResource());

  if (handler != null) {
    world.getResource<GenerationHandlerResource>().registerDefault(handler);
  }
  world.flush();

  return world;
}

/// Helper to spawn a scene entity.
Entity spawnScene(World world) =>
    world.spawnComponents([const Scene(), SceneFrame()]);

/// Helper to spawn an actor entity in a scene.
Entity spawnActor(
  World world,
  Entity sceneEntity, {
  String systemPrompt = 'You are a helpful assistant.',
  String? openDecisionPrompt,
  SchemaBundle schema = SchemaBundle.empty,
}) {
  final actorId = AgentId.create();
  final modelId = ModelId.create();
  final components = <Component>[
    Actor(agentId: actorId),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: systemPrompt),
    PresentInScene(sceneEntity: sceneEntity),
  ];
  if (openDecisionPrompt != null) {
    components.add(OpenDecision(prompt: openDecisionPrompt, schema: schema));
  }
  return world.spawnComponents(components);
}

/// Spawn a complete text beat in [thread], indexed under [keywords].
Entity addIndexedBeat(
  World world,
  Entity thread,
  Entity speaker,
  String text,
  Iterable<String> keywords,
) {
  final beat = startBeat(world, thread, speaker, BeatModalityEnum.text);
  appendToBeat(world, beat, text);
  completeBeat(world, beat);
  indexBeat(world, beat, keywords);
  world.flush();
  return beat;
}

/// Drive agency grant + projection for the given world.
void projectFor(World world) {
  world.runSchedule('AgencyGrant');
  world.flush();
  world.runSchedule('Project');
  world.flush();
}

/// All beats in [world] whose [TextContent] contains [text].
List<Entity> beatsWithText(World world, String text) => world
    .query2<TextContent, BeatStatus>()
    .where((t) => t.$1.get<TextContent>()?.text.contains(text) ?? false)
    .map((t) => t.$1.entity)
    .toList();
