import 'dart:io';
import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class _H implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'step'},
      rawOutput: 'step',
      toolCalls: const [
        ToolCall(
          name: ToolName('write'),
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
  final jail = await Directory.systemTemp.createTemp('ledp_');
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
    ActorThreads(threads: const []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'write out.txt'),
  ]);
  world.flush();

  final ledger = HarnessExecutionLedger(world);
  world.executionObserver = ledger;

  final loop = HarnessLoop(world: world);
  var ticks = 0;
  while (!loop.canSleep() && ticks < 30) {
    ledger.beginTick();
    loop.tickForDebug();
    await Future<void>.delayed(Duration.zero);
    ticks++;
    if (ticks == 5 || ticks == 10 || ticks == 20) {
      // ignore: avoid_print
      print('--- tick $ticks ---');
      // ignore: avoid_print
      print(ledger.dump());
    }
  }
  // ignore: avoid_print
  print('exited after $ticks ticks; canSleep=${loop.canSleep()}');
  // ignore: avoid_print
  print(ledger.dump());
  await jail.delete(recursive: true);
}
