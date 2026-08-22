// ignore_for_file: lines_longer_than_80_chars

/// Deterministic tests for the guided-decision tool protocol.
///
/// Proves, with no real model:
/// 1. `decisionSchema` builds a valid AnyOf covering every registered tool
///    plus the Answer choice.
/// 2. `decodeDecision` maps structured output back to a ToolCall or answer.
/// 3. The full loop works end-to-end: a scripted inner handler that emits a
///    structured "act" gets its tool executed by the world and the result
///    lands as a beat — same canonical path as native tool calling.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

ToolDef _echoTool() => ToolDef(
  name: const ToolName('echo'),
  description: 'Echo back the message',
  argsSchema: SchemaBundle(
    root: FM.object(
      'echo',
      properties: () => [FM.prop('message', FM.string())],
    ),
  ),
  execute: (args) async => 'echo:${(args as Map)['message']}',
);

void main() {
  group('decisionSchema', () {
    test('covers every tool plus Answer', () {
      final registry = ToolRegistry()..register(_echoTool());
      final schema = decisionSchema(registry);
      expect(schema.isEmpty, isFalse);
      expect(schema.root, isA<AnyOfSchema>());
      final choices = (schema.root as AnyOfSchema).choices;
      expect(
        choices.whereType<ObjectSchema>().any((c) => c.name == 'Answer'),
        isTrue,
      );
      expect(
        choices.whereType<ObjectSchema>().any((c) => c.name == 'Act_echo'),
        isTrue,
      );
    });
  });

  group('decodeDecision', () {
    test('maps an act to a ToolCall', () {
      final registry = ToolRegistry()..register(_echoTool());
      final decoded = decodeDecision({
        'Act_echo': {'tool': 'echo', 'message': 'hi'},
      }, registry);
      expect(decoded.answer, isNull);
      expect(decoded.call!.name.value, 'echo');
      expect(decoded.call!.arguments['message'], 'hi');
    });

    test('maps an answer to text', () {
      final registry = ToolRegistry()..register(_echoTool());
      final decoded = decodeDecision({
        'Answer': {'text': 'done'},
      }, registry);
      expect(decoded.call, isNull);
      expect(decoded.answer, 'done');
    });
  });

  group('StructuredToolDecisionHandler', () {
    test('end-to-end: guided act executes as a world tool call', () async {
      final world = World()..addPlugin(AgentPlugin());
      final router = ModelRouter(inferenceClientsBuilders: {});
      const modelId = ModelId('mock');
      router.models[modelId] = Model(id: modelId, tier: 0);
      world
        ..upsertResource(ModelRouterResource(router))
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(AgencyPolicy(maxConcurrent: 1))
        ..flush();

      // Inner handler: emits one guided act, then a final answer.
      var calls = 0;
      final inner = ScriptedDecisionInner(onGenerate: () => ++calls);
      world.getResource<GenerationHandlerResource>().registerDefault(
        StructuredToolDecisionHandler(inner: inner),
      );

      final registry = ToolRegistry()
        ..register(_echoTool())
        ..register(writeTool(FsToolsRoot('/tmp/structured_tools_test')));
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

      await HarnessLoop(world: world).runUntilIdle();

      // One decision was made (guided act); the echo tool ran in-world and
      // the tool result became a beat on the canonical path.
      expect(calls, 1);
      final toolBeats = world
          .query3<ToolResultContent, BeatStatus, TextContent>()
          .where((r) => r.$2.name == 'echo')
          .toList();
      expect(toolBeats, hasLength(1));
      expect(toolBeats.first.$4.text, contains('echo:hi'));
    });
  });
}

/// Minimal inner handler standing in for a real backend: first call returns
/// a guided "act" choosing echo; second call returns the final answer.
class ScriptedDecisionInner implements GenerationHandler {
  ScriptedDecisionInner({required this.onGenerate});
  final void Function() onGenerate;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    onGenerate();
    final isFirst = callsSeen++ == 0;
    final output = isFirst
        ? <String, dynamic>{
            'Act_echo': {'tool': 'echo', 'message': 'hi'},
          }
        : <String, dynamic>{
            'Answer': {'text': 'all done'},
          };
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: output,
      rawOutput: '',
      taskId: request.taskId,
    );
  }

  int callsSeen = 0;
}
