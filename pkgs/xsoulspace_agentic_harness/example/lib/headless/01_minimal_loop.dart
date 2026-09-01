/// Golden example 01 — minimal headless agent loop, no Flutter, no LLM.
// ignore_for_file: avoid_print, file_names

///
/// Run from `pkgs/xsoulspace_inference_core/example`:
///
/// ```sh
/// dart run lib/headless/01_minimal_loop.dart
/// ```
///
/// This is the smallest complete harness: build a world, register a
/// [GenerationHandler], spawn one actor with one open decision, and let
/// [HarnessLoop] drive everything until idle.
library;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// A tiny fake model. A real backend (Gemma, Apple Foundation, OpenRouter)
/// would implement the same one-method interface — see
/// `04_real_model_openrouter.dart`.
class EchoHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    const text = 'The actor decided: proceed north.';
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': text},
      rawOutput: text,
      taskId: request.taskId,
    );
    // Responses travel through the world's event channel — never by direct
    // mutation. ProcessResponses picks this up on the next tick.
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> main() async {
  // 1. Build the world and install the agent plugin (components + systems).
  final world = World()..addPlugin(AgentPlugin());

  // 2. Register the two resources every harness world needs.
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource());

  // 3. Wire the handler. Real apps register per-model handlers via
  //    ModelRouter; the default handler slot is enough here.
  world.getResource<GenerationHandlerResource>().registerDefault(
        EchoHandler(),
      );
  world.flush();

  // 4. Spawn scene + actor + thread with the shared bootstrap facade.
  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();
  final actors = setup.spawnActors([
    ActorSpec(
      name: 'navigator',
      systemPrompt: 'You are a ship navigator. Decide concisely.',
    ),
  ], scene);
  final actor = actors.single;

  // 5. Open a decision. Agency is granted only when real work exists —
  //    this component is what wakes the model up.
  world.upsertComponent(
    actor.entity,
    const OpenDecision(prompt: 'Storm ahead. Do we change course?'),
  );
  world.flush();

  // 6. Drive the loop until nothing is left to do. In an app you would
  //    instead `await HarnessLoop(world: world).start()` and push new
  //    decisions via wakeup().
  await HarnessLoop(world: world).runUntilIdle();

  // 7. Observe results: beats are indexed in FacetIndex as they are written;
  //    projection ray-traces memory from them. The actor must be fully idle.
  final index = world.getResource<FacetIndex>();
  final beats = index.beatsFor(const ['decided']).toList();
  print('beats matching "decided": ${beats.length}');
  print('actor has OpenDecision: '
      '${world.getEntity(actor.entity).$1.has<OpenDecision>()}');
  print('actor has Agency: '
      '${world.getEntity(actor.entity).$1.has<Agency>()}');
}
