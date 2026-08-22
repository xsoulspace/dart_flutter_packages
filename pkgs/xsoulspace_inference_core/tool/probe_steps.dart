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
  final jail = await Directory.systemTemp.createTemp('probe4_');
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
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'write out.txt'),
  ]);
  world.flush();

  print('actor valid after flush: ${world.getEntity(actor).$2}');
  print(
    'has OpenDecision: '
    '${world.getEntity(actor).$1.get<OpenDecision>() != null}',
  );
  print('canSleep before any tick: ${HarnessLoop(world: world).canSleep()}');

  // Manual schedule stepping with visibility.
  for (var step = 0; step < 8; step++) {
    print('--- manual step $step ---');
    if (world.hasSchedule('AgencyGrant')) {
      world.runSchedule('AgencyGrant');
      world.flush();
    }
    final hasAgency = world.query2<Actor, Agency>().toList().isNotEmpty;
    print('  after AgencyGrant: agency=$hasAgency');

    if (world.hasSchedule('Project')) {
      world.runSchedule('Project');
      world.flush();
    }

    if (world.hasSchedule('ActorAct')) {
      await world.runScheduleAsync('ActorAct');
      world.flush();
    }
    final respCount = world.events.reader<ActorGenerateResponse>().length;
    print('  after ActorAct: responses=$respCount');

    if (world.hasSchedule('ProcessResponses')) {
      world.runSchedule('ProcessResponses');
      world.flush();
    }
    final callCount = world.events.reader<ToolCallEvent>().length;
    print('  after ProcessResponses: toolCalls=$callCount');

    if (world.hasSchedule('Mechanical')) {
      world.runSchedule('Mechanical');
      world.flush();
    }
    final resultCount = world.events.reader<ToolResultEvent>().length;
    print('  after Mechanical: toolResults=$resultCount');

    for (final r
        in world
            .query3<ToolResultContent, BeatStatus, TextContent>()
            .toList()) {
      print('  tool beat: ${r.$2.name} out=${r.$2.output}');
    }
    final f = File('${jail.path}/out.txt');
    print(
      '  file: ${f.existsSync() ? '"${f.readAsStringSync()}"' : 'missing'}',
    );

    if (HarnessLoop(world: world).canSleep()) {
      print('  -> idle');
      break;
    }
  }
  await jail.delete(recursive: true);
}
