// ignore_for_file: lines_longer_than_80_chars

/// Regression: tool-call continuation (ReAct loop).
///
/// Assumption under test: after a response carrying tool calls is processed,
/// the actor's decision is consumed and NOTHING re-opens a decision once the
/// tool result lands as a beat. The world goes idle with the tool result
/// sitting in the graph — the agent never sees it and never continues.
///
/// Expected behavior (post-fix): when the last pending tool task for an
/// actor's decision resolves, the actor gets a continuation decision whose
/// projection includes the tool-result beat, so it can act on what it learned.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// Handler that issues one write, then (on its second call) answers.
///
/// The second call only happens if the harness re-opens a decision after the
/// tool result lands — this is the observable "continuation happened" signal.
class _WriteThenAnswerHandler implements GenerationHandler {
  int calls = 0;
  final List<String> prompts = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    calls++;
    prompts.add(request.prompt);
    final isFirst = calls == 1;
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'step $calls'},
      rawOutput: 'step $calls',
      toolCalls: isFirst
          ? [
              ToolCall(
                name: const ToolName('write'),
                arguments: {'path': 'out.txt', 'content': 'hello'},
              ),
            ]
          : const [],
      taskId: request.taskId,
    );
  }
}

World _buildWorld(String jailPath, GenerationHandler handler) {
  final world = World()..addPlugin(AgentPlugin());
  final router = ModelRouter(inferenceClientsBuilders: {});
  const modelId = ModelId('m');
  router.models[modelId] = Model(id: modelId, tier: 0);
  world
    ..upsertResource(ModelRouterResource(router))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(maxConcurrent: 1))
    ..flush();
  world.getResource<GenerationHandlerResource>().registerDefault(handler);
  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jailPath)).forEach(registry.register);
  world.getResource<ToolRegistryResource>().register('default', registry);

  final scene = spawnScene(world);
  spawnActor(world, scene, openDecisionPrompt: 'write out.txt');
  world.flush();
  return world;
}

void main() {
  test(
    'actor gets a continuation decision after its tool result lands',
    () async {
      final jail = await Directory.systemTemp.createTemp('continuation_');
      addTearDown(() => jail.delete(recursive: true));

      final handler = _WriteThenAnswerHandler();
      final world = _buildWorld(jail.path, handler);
      await HarnessLoop(world: world).runUntilIdle();

      // The file was written — the tool executed.
      expect(File('${jail.path}/out.txt').existsSync(), isTrue);

      // THE ASSUMPTION UNDER TEST: the handler must be called twice —
      // once for the initial decision, once to act on the tool result.
      // Pre-fix this fails: calls == 1, the world goes idle and the tool
      // result beat is never projected back to the actor.
      expect(
        handler.calls,
        2,
        reason:
            'actor must receive a continuation decision after the tool '
            'result lands; otherwise it can never iterate on tool output '
            '(the ReAct loop is broken at the harness level)',
      );

      // The continuation prompt's projection must include the tool result
      // so the model can see what happened. The prompt itself is unchanged,
      // but the context fragments carry the projected beats.
      expectIdle(world);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
