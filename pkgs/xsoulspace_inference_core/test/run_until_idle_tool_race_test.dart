// ignore_for_file: lines_longer_than_80_chars

/// Regression: `HarnessLoop.runUntilIdle` must not exit while a
/// response-carried tool call is still executing.
///
/// Root cause (2026-08): `processResponsesSystem` dispatched response
/// `toolCalls` as `ToolCallEvent`s WITHOUT a `taskId`, so no task was
/// registered in `TaskRegistryResource`. `canSleep()` only checks the task
/// registry — it saw "no in-flight work" while the async tool execution was
/// still running, and `runUntilIdle` exited. The `ToolResultEvent` landed in
/// a dead loop: the file was never written, the result never became a beat.
///
/// The manual-schedule tests (`harness_headless_tools_test.dart`) never hit
/// this because they hardcode a 50ms sleep + a second `Mechanical` pass —
/// a crutch `runUntilIdle` (the CLI/server production path) doesn't have.
///
/// Fix: response-carried tool calls now register a `TaskHandle` and carry
/// its `taskId`; `toolExecutionSystem` resolves it on completion, keeping
/// `canSleep()` false until the tool is done.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

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

World _buildWorld(String jailPath) {
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
  world.getResource<GenerationHandlerResource>().registerDefault(
    _ToolEmittingHandler(),
  );
  final registry = ToolRegistry();
  fsTools(FsToolsRoot(jailPath)).forEach(registry.register);
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
  return world;
}

void main() {
  test(
    'runUntilIdle waits for async response-carried tool execution',
    () async {
      final jail = await Directory.systemTemp.createTemp('regression_idle_');
      addTearDown(() => jail.delete(recursive: true));

      final world = _buildWorld(jail.path);
      await HarnessLoop(world: world).runUntilIdle();

      // The loop must not exit before the async write completed.
      final file = File('${jail.path}/out.txt');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'runUntilIdle exited while the response-carried tool call was '
            'still in flight — the write was lost. canSleep() must account '
            'for tool tasks dispatched by processResponsesSystem.',
      );
      expect(file.readAsStringSync(), 'hello');

      // And the tool result must have landed as a beat in the graph.
      final toolBeats = world
          .query3<ToolResultContent, BeatStatus, TextContent>()
          .toList();
      expect(toolBeats, isNotEmpty);
      expect(toolBeats.first.$2.name, 'write');

      // Nothing stranded anywhere — the canonical end-of-test assertion.
      expectIdle(world);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'ledger shows channel flow across schedules',
    () async {
      final jail = await Directory.systemTemp.createTemp('ledger_');
      addTearDown(() => jail.delete(recursive: true));

      final world = _buildWorld(jail.path);
      final ledger = HarnessExecutionLedger(world);
      world.executionObserver = ledger;

      await HarnessLoop(world: world).runUntilIdle();

      // The ledger must show the full event journey at schedule granularity:
      // a response arrives and is consumed, tool calls are dispatched and
      // consumed. ToolResultEvent 0→1 may land between observed systems
      // (tool execution is fire-and-forget), so we only assert its consumption.
      final dump = ledger.dump();
      expect(dump, contains('ActorGenerateResponse 0→1'));
      expect(dump, contains('ActorGenerateResponse 1→0'));
      expect(dump, contains('ToolCallEvent 0→1'));
      expect(dump, contains('ToolCallEvent 1→0'));
      expect(dump, contains('ToolResultEvent 1→0'));

      expectIdle(world);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('canSleep stays false while a tool task is registered', () async {
    final jail = await Directory.systemTemp.createTemp('regression_sleep_');
    addTearDown(() => jail.delete(recursive: true));

    final world = _buildWorld(jail.path);
    final loop = HarnessLoop(world: world);

    // Drive one tick at a time; after ProcessResponses dispatches the tool
    // call, the registry must hold its task until execution completes.
    var sawTaskDuringFlight = false;
    for (var i = 0; i < 20; i++) {
      loop.tickForDebug();
      await Future<void>.delayed(Duration.zero);
      if (!world.getResource<TaskRegistryResource>().isEmpty) {
        sawTaskDuringFlight = true;
      }
      if (loop.canSleep()) break;
    }
    expect(
      sawTaskDuringFlight,
      isTrue,
      reason: 'tool execution should be visible as an in-flight task',
    );

    // ADR 0004: this handler ALWAYS emits a tool call, so the ReAct
    // continuation keeps re-opening decisions until maxToolRounds. The
    // world legitimately does NOT settle idle here anymore — instead assert
    // the bounded-loop invariant: after enough ticks the chain exhausts its
    // round budget and the actor stops.
    for (var i = 0; i < 500 && !loop.canSleep(); i++) {
      loop.tickForDebug();
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      loop.canSleep(),
      isTrue,
      reason: 'loop must settle once maxToolRounds is exhausted',
    );
    final actorRounds = world.query2<Actor, ToolRoundCount>().toList();
    if (actorRounds.isNotEmpty) {
      expect(
        actorRounds.first.$2.value,
        lessThanOrEqualTo(16),
        reason: 'ToolRoundCount must never exceed AgencyPolicy.maxToolRounds',
      );
    }
  });
}
