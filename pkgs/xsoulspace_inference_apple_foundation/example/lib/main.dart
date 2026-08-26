import 'dart:async';

import 'package:flutter/material.dart';

import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation_flutter.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

// ecsly types are re-exported via xsoulspace_inference_core

void main() => runApp(const AppleFoundationExampleApp());

class AppleFoundationExampleApp extends StatelessWidget {
  const AppleFoundationExampleApp({super.key});

  @override
  Widget build(final BuildContext context) => MaterialApp(
    title: 'Apple Foundation Example',
    theme: ThemeData.from(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    ),
    home: const _ExamplePage(),
  );
}

class _ExamplePage extends StatefulWidget {
  const _ExamplePage();

  @override
  State<_ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<_ExamplePage> {
  String _status = 'Idle';
  bool? _available;

  Future<void> _checkAvailability() async {
    setState(() => _status = 'Checking...');
    final available = await AppleFoundationInferenceClient(
      api: AppleFoundationInferenceClient.initApi(),
    ).refreshAvailability();
    setState(() {
      _available = available;
      _status = available
          ? 'Available'
          : 'Unavailable (macOS 26+ and Apple Intelligence required)';
    });
  }

  Future<void> _runEcsHarness() async {
    setState(() => _status = 'Running ECS harness...');

    // Build the world with the agent plugin
    final world = World()..addPlugin(AgentPlugin());

    // Register the model router resource
    final router = ModelRouter(
      inferenceClientsBuilders: {
        DefaultModelNames.appleFoundation: () => AppleFoundationInferenceClient(
          api: AppleFoundationInferenceClient.initApi(),
        ),
      },
    );
    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..flush();

    // Register the default generation handler
    final handler = DefaultGenerationHandler()..router = router;
    world.getResource<GenerationHandlerResource>().registerDefault(handler);
    world.flush();

    // Spawn a scene
    final sceneEntity = world.spawnComponents([const Scene(), SceneFrame()]);

    // Spawn an actor with a goal
    final actorId = AgentId.create();
    final modelId = ModelId.create();
    final actorEntity = world.spawnComponents([
      Actor(agentId: actorId),
      ActorModel(modelId: modelId),
      const ActorSystemPrompt(text: 'You are a helpful assistant.'),
      ActorThreads(threads: []),
      PresentInScene(sceneEntity: sceneEntity),
    ]);

    // Create an open decision — this triggers the agency loop
    world.upsertComponent(
      actorEntity,
      const OpenDecision(prompt: 'Reply with one short word: hello.'),
    );
    world.flush();

    // Run the harness loop — it handles agency grant, projection,
    // actor act, response processing, and idle/sleep automatically.
    final loop = HarnessLoop(world: world);
    await loop.runUntilIdle();

    // Read the projected cut: the indexed beats the actor handled. The cut is a
    // derived view (Situation) rebuilt each decision, so read the facet index.
    final index = world.getResource<FacetIndex>();
    final responseBeats = index.beatsFor(const ['hello']).toList();
    setState(() {
      if (responseBeats.isNotEmpty) {
        final text = world
            .getEntity(responseBeats.first)
            .$1
            .get<TextContent>()
            ?.text;
        _status = text == null ? 'No response received' : 'OK: $text';
      } else {
        _status = 'No response received';
      }
    });
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apple Foundation Example')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_available != null)
            Text(
              'Engine: ${_available! ? "Available" : "Unavailable"}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _checkAvailability,
            child: const Text('Check availability'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _available == true ? _runEcsHarness : null,
            child: const Text('Run ECS harness'),
          ),
          const SizedBox(height: 24),
          Text(_status, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    ),
  );
}
