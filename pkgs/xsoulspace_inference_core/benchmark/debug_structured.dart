// ignore_for_file: avoid_print

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main() async {
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('mock');
  router.models[modelId] = Model(id: modelId, tier: 0);
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..flush();

  final inner = ScriptedDecisionInner();
  world.getResource<GenerationHandlerResource>().registerDefault(
    StructuredToolDecisionHandler(inner: inner),
  );

  final registry = ToolRegistry()
    ..register(
      ToolDef(
        name: const ToolName('echo'),
        description: 'Echo',
        argsSchema: SchemaBundle(
          root: FM.object(
            'echo',
            properties: () => [FM.prop('message', FM.string())],
          ),
        ),
        execute: (args) async => 'echo:${(args as Map)['message']}',
      ),
    );
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'say hi via echo'),
  ]);
  world.flush();

  for (var tick = 0; tick < 20; tick++) {
    await Future<void>.delayed(Duration.zero);
    HarnessLoop(world: world).tickForDebug();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    world.flush();
    final open = world.query2<Actor, OpenDecision>().length;
    final awaiting = world.query2<Actor, AwaitingResponse>().length;
    final tasks = world.getResource<TaskRegistryResource>().tasks.length;
    print('tick $tick open=$open awaiting=$awaiting tasks=$tasks');
    if (open == 0 && awaiting == 0 && tasks == 0) break;
  }
  print('inner calls: ${inner.callsSeen}');
}

class ScriptedDecisionInner implements GenerationHandler {
  int callsSeen = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    callsSeen++;
    final isFirst = callsSeen == 1;
    final output = isFirst
        ? {
            'Act_echo': {'tool': 'echo', 'message': 'hi'},
          }
        : {
            'Answer': {'text': 'all done'},
          };
    print('inner.generate #$callsSeen schemaEmpty=${request.schema.isEmpty}');
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: output,
      rawOutput: '',
      taskId: request.taskId,
    );
  }
}
