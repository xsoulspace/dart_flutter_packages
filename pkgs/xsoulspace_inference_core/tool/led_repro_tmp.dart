import 'dart:io';
import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

class _ToolEmittingHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'writing'},
      rawOutput: 'writing',
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

void main() async {
  final jail = await Directory.systemTemp.createTemp('ledger_dbg_');
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('m');
  router.models[modelId] = Model(id: modelId, name: DefaultModelNames.appleFoundation);
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..flush();
  world.getResource<GenerationHandlerResource>().registerDefault(_ToolEmittingHandler());
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

  final loop = HarnessLoop(world: world);
  for (var i = 0; i < 12; i++) {
    loop.tickForDebug();
    await Future<void>.delayed(Duration.zero);
    final decision = world.query2<Actor, OpenDecision>().length;
    final agency = world.query2<Actor, Agency>().length;
    final awaiting = world.query2<Actor, AwaitingResponse>().length;
    final tasks = world.getResource<TaskRegistryResource>().length;
    // ignore: avoid_print
    print('tick $i: decision=$decision agency=$agency awaiting=$awaiting tasks=$tasks '
        'resp=${world.events.reader<ActorGenerateResponse>().length} '
        'call=${world.events.reader<ToolCallEvent>().length} '
        'result=${world.events.reader<ToolResultEvent>().length}');
  }
  await jail.delete(recursive: true);
}
