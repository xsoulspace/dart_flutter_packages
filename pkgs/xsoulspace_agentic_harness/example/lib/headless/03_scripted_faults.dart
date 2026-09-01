/// Golden example 03 — deterministic fault injection with a scripted model.
// ignore_for_file: avoid_print, file_names

///
/// Run from `pkgs/xsoulspace_inference_core/example`:
///
/// ```sh
/// dart run lib/headless/03_scripted_faults.dart
/// ```
///
/// Everything except "write a beat" is deterministic graph logic, so the
/// whole harness is testable without an LLM. [ScriptedGenerationHandler]
/// replaces the model with declarative turns; fault modes exercise the
/// retry/timeout paths. Here the first turn is `empty`, which must trigger
/// the retry path and replay the same behavior.
library;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

Future<void> main() async {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource());

  // Turn 1: empty response -> the harness retries. Turn 2: real answer.
  // Every request served is recorded for oracle assertions.
  final handler = ScriptedGenerationHandler([
    ScriptedTurn(mode: ScriptedTurnMode.empty),
    ScriptedTurn(text: 'Recovered after the empty response.'),
  ]);
  world.getResource<GenerationHandlerResource>().registerDefault(handler);
  world.flush();

  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();
  final actors = setup.spawnActors([
    ActorSpec(name: 'test-subject', systemPrompt: 'Answer briefly.'),
  ], scene);
  world.upsertComponent(
    actors.single.entity,
    const OpenDecision(prompt: 'Say something.'),
  );
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();

  // Oracle assertions — exactly what a test would check:
  print('generation requests served: ${handler.requests.length}');
  print('expected >= 2 (first attempt + retry): '
      '${handler.requests.length >= 2}');
  print('actor idle: '
      '${!world.getEntity(actors.single.entity).$1.has<AwaitingResponse>()}');
}
