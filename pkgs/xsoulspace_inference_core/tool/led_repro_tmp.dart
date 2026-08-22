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

  // Reset watermark counters so the ledger deltas are per-run.
  world.events.channel<ActorGenerateRequest>().resetStats();
  world.events.channel<ActorGenerateResponse>().resetStats();
  world.events.channel<ActorGenerateStreamEvent>().resetStats();
  world.events.channel<ToolCallEvent>().resetStats();
  world.events.channel<ToolResultEvent>().resetStats();

  final ledger = HarnessExecutionLedger(world);
  world.executionObserver = ledger;
  try {
    await HarnessLoop(world: world).runUntilIdle();
  } on Object catch (e) {
    // ignore: avoid_print
    print('CAUGHT: $e');
  }
  // Show ToolResultEvent watermark at each entry.
  for (final e in ledger.entries) {
    final b = e.channelCountsBefore['ToolResultEvent'];
    final a = e.channelCountsAfter['ToolResultEvent'];
    if (b != a) {
      // ignore: avoid_print
      print('${e.schedule}.${e.system}: $b→$a');
    }
  }
  await jail.delete(recursive: true);
}
