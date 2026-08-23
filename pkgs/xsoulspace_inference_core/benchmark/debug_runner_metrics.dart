// ignore_for_file: avoid_print

import 'dart:io';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main() async {
  final jail = await Directory.systemTemp.createTemp('repro_metrics_');
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('suite-model');
  router.models[modelId] = Model(
    id: modelId,
    name: DefaultModelNames.appleFoundation,
  );
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..flush();

  var callsSeen = 0;
  world.getResource<GenerationHandlerResource>().registerDefault(
    StructuredToolDecisionHandler(
      inner: _ScriptedInner(() => ++callsSeen),
    ),
  );

  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jail.path)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: 'sys'),
    ActorThreads(threads: []),
    const ActorTools(registryName: 'default'),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: 'write out.txt with hello'),
  ]);
  world.flush();

  final loop = HarnessLoop(world: world);
  await loop.runUntilIdle();

  print('inner calls: $callsSeen');
  print('file exists: ${File('${jail.path}/out.txt').existsSync()}');
  final beats = world
      .query3<ToolResultContent, BeatStatus, TextContent>()
      .toList();
  print('tool beats: ${beats.length}');
  for (final b in beats) {
    print('  \$2=${b.$2.runtimeType} name=${b.$2 is ToolResultContent ? (b.$2 as ToolResultContent).name : 'n/a'}');
  }
  await jail.delete(recursive: true);
}

class _ScriptedInner implements GenerationHandler {
  _ScriptedInner(this.counter);
  final int Function() counter;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final n = counter();
    if (n == 1) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {
          'Act_write': {'tool': 'write', 'path': 'out.txt', 'content': 'hello'},
        },
        rawOutput: '',
        taskId: request.taskId,
      );
    }
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {
        'Answer': {'text': 'done'},
      },
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}
