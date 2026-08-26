/// Golden example 04 — driving the harness with a REAL model.
// ignore_for_file: avoid_print, file_names

///
/// Run from `pkgs/xsoulspace_inference_core/example`:
///
/// ```sh
/// OPENROUTER_API_KEY=sk-or-... dart run lib/headless/04_real_model_openrouter.dart
/// ```
///
/// Exits early with instructions when `OPENROUTER_API_KEY` is not set.
///
/// The swap point for any other provider is the [ModelRouter]: register an
/// [InferenceClient] builder per [ModelName]. To use on-device Gemma
/// instead, depend on `xsoulspace_inference_gemma_flutter` and register:
///
/// ```dart
/// inferenceClientsBuilders: {
///   GemmaModelNames.gemma: () => GemmaFlutterInferenceClient(),
/// }
/// ```
///
/// For Apple Foundation Models use `AppleFoundationNativeClient` from
/// `xsoulspace_inference_apple_foundation`. The handler, loop, tools, and
/// world stay identical — only the reasoning primitive changes.
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// The model id actors reference via their [ActorModel] component.
const _modelId = ModelId('openrouter-cheap');

Future<void> main() async {
  final apiKey = Platform.environment['OPENROUTER_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Set OPENROUTER_API_KEY to run this example.');
    print('  OPENROUTER_API_KEY=sk-or-... '
        'dart run lib/headless/04_real_model_openrouter.dart');
    exit(0);
  }

  final world = World()..addPlugin(AgentPlugin());

  // Register the real client behind its model name; the router lazily builds
  // and caches the runtime on first use.
  final router = ModelRouter(
    inferenceClientsBuilders: {
      OpenRouterModelNames.openRouter: () =>
          OpenRouterInferenceClient(apiKey: apiKey),
    },
    models: {
      _modelId: const Model(id: _modelId, name: OpenRouterModelNames.openRouter),
    },
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource());
  world.getResource<GenerationHandlerResource>().registerDefault(
        DefaultGenerationHandler(router: router),
      );
  world.flush();

  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();
  final actors = setup.spawnActors([
    ActorSpec(
      name: 'assistant',
      systemPrompt: 'You are terse. Answer in one sentence.',
    ),
  ], scene);
  final actor = actors.single;

  // Bind the actor to the registered model, then open a decision.
  world
    ..upsertComponent(actor.entity, ActorModel(modelId: _modelId))
    ..upsertComponent(
      actor.entity,
      const OpenDecision(prompt: 'In one sentence: why is the sky blue?'),
    );
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();

  final index = world.getResource<FacetIndex>();
  print('beats about "sky": ${index.beatsFor(const ['sky']).length}');
}
