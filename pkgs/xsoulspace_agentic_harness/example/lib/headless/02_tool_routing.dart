/// Golden example 02 — tools route through the world, not the handler.
// ignore_for_file: avoid_print, file_names

///
/// Run from `pkgs/xsoulspace_inference_core/example`:
///
/// ```sh
/// dart run lib/headless/02_tool_routing.dart
/// ```
///
/// The handler emits a [ToolCall] the way any backend would (native function
/// calling or text tags). It never executes the tool itself: the world's
/// `toolExecutionSystem` resolves it against the actor's [ToolRegistry],
/// runs the executor, and writes a tool-result beat into the actor's thread.
/// This is the same path Apple Foundation native calls and OpenRouter
/// `tool_calls` take.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// Fake model: answers the first round with one `lookup_course` call, then
/// with plain text once the tool result is in the projection — mirroring how
/// a real model behaves across tool-continuation rounds.
class ToolCallingHandler implements GenerationHandler {
  var _called = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final toolCalls = _called
        ? const <ToolCall>[]
        : [
            ToolCall(
              name: const ToolName('lookup_course'),
              arguments: {'destination': 'harbor'},
            ),
          ];
    _called = true;
    final text = toolCalls.isEmpty ? 'Course set: NW 315°.' : 'Checking the charts.';
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': text},
      rawOutput: text,
      toolCalls: toolCalls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> main() async {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource());
  world.getResource<GenerationHandlerResource>().registerDefault(
        ToolCallingHandler(),
      );
  world.flush();

  final setup = AgentWorldSetup(world: world);
  final scene = setup.spawnScene();

  // Register a tool on the 'default' registry. Every actor bound to that
  // registry can call it; its schema is what the model sees.
  setup.registerTools([
    ToolDef.encode(
      name: const ToolName('lookup_course'),
      description: 'Look up the sailing course to a destination.',
      execute: (args) async {
        final destination =
            args is Map ? args['destination']?.toString() : '$args';
        return {'course': 'NW 315°', 'destination': destination};
      },
    ),
  ]);

  final actors = setup.spawnActors([
    ActorSpec(name: 'navigator', systemPrompt: 'You navigate the ship.'),
  ], scene);
  final actor = actors.single;

  world.upsertComponent(
    actor.entity,
    const OpenDecision(prompt: 'Set a course for the harbor.'),
  );
  world.flush();

  await HarnessLoop(world: world).runUntilIdle();

  // The tool result is now part of the narrative graph: find beats via the
  // facet index and read their tool-result content component.
  final index = world.getResource<FacetIndex>();
  final results = index.beatsFor(const ['course', 'harbor']).toList();
  print('tool-related beats: ${results.length}');
  for (final entity in results) {
    final content = world.getEntity(entity).$1.get<ToolResultContent>();
    if (content != null) print('tool result beat: ${content.output}');
  }
}
