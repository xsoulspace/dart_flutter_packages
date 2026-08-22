import 'dart:io';
import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class _H implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'step'},
      rawOutput: 'step',
      toolCalls: [
        ToolCall(
          name: const ToolName('write'),
          arguments: {'path': 'out.txt', 'content': 'hello'},
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> main() async {
  final jail = await Directory.systemTemp.createTemp('probe3_');
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('m');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..flush();
  world.getResource<GenerationHandlerResource>().registerDefault(_H());
  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'write out.txt'),
  ]);
  world.flush();

  // Trace every event on both channels as the loop runs.
  final loop = HarnessLoop(world: world);
  var tick = 0;
  while (!loop.canSleep() && tick < 50) {
    print('[tick $tick] --- pre-tick ---');
    print(
      '  responses in channel: '
      '${world.events.reader<ActorGenerateResponse>().length}',
    );
    print(
      '  toolCalls in channel: '
      '${world.events.reader<ToolCallEvent>().length}',
    );

    loop.tickForDebug();

    final postResponses = world.events.reader<ActorGenerateResponse>().drain();
    final postCalls = world.events.reader<ToolCallEvent>().drain();
    if (postResponses.isNotEmpty || postCalls.isNotEmpty) {
      print(
        '[tick $tick] UNCONSUMED after schedules: '
        '${postResponses.length} responses, ${postCalls.length} calls',
      );
      for (final r in postResponses) {
        print(
          '  resp raw="${r.rawOutput}" tools=${r.toolCalls.length} '
          'args=${r.toolCalls.isEmpty ? '-' : r.toolCalls.first.arguments}',
        );
      }
      for (final c in postCalls) {
        print('  call tool=${c.call.name.value} args=${c.call.arguments}');
      }
    }
    for (final r
        in world
            .query3<ToolResultContent, BeatStatus, TextContent>()
            .toList()) {
      print('[tick $tick] tool beat: ${r.$2.name} out=${r.$2.output}');
    }
    final f = File('${jail.path}/out.txt');
    if (f.existsSync()) {
      print('[tick $tick] FILE content="${f.readAsStringSync()}"');
    }
    tick++;
  }
  print(
    'done after $tick ticks; file='
    '${File('${jail.path}/out.txt').existsSync() ? File('${jail.path}/out.txt').readAsStringSync() : 'missing'}',
  );
  await jail.delete(recursive: true);
}
