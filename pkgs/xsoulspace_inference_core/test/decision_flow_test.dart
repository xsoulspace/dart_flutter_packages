// ignore_for_file: lines_longer_than_80_chars

/// ADR 0005 — DecisionFlow: composable decision-creation API.
///
/// Policies are pure functions; the applying system is mechanical. These
/// tests cover: builder triggers/effects, first-match flow evaluation,
/// per-policy attribution via DecisionOrigin, end-to-end custom flows, and
/// deferred thinking ("dreaming").
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'dart:io';

import 'support/agent_harness_support.dart';

World _world(DecisionFlow flow) {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(DecisionFlowResource(flow))
    ..flush();
  return world;
}

void main() {
  group('policy builders (pure evaluation)', () {
    test('onToolResult fires only when the marker is present', () {
      final world = _world(DecisionFlow([]));
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      final policy = onToolResult().thenOpen(prompt: 'continue');
      final ctx = DecisionContext(actor: actor, world: world, tick: 1);

      expect(policy.evaluate(ctx), isNull);
      world.getEntity(actor).$1.insert(const ToolResultPendingMarker());
      world.flush();
      final draft = policy.evaluate(ctx);
      expect(draft?.prompt, 'continue');
    });

    test('everyNTicks fires on multiples of n only', () {
      final world = _world(DecisionFlow([]));
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      final policy = whenIdleEveryNTicks(10).thenDream('review');
      bool eval(int tick) =>
          policy.evaluate(
            DecisionContext(actor: actor, world: world, tick: tick),
          ) !=
          null;
      // Tick 0 does not fire (avoids a decision storm at startup).
      expect(eval(0), isFalse);
      expect(eval(9), isFalse);
      expect(eval(10), isTrue);
      expect(eval(20), isTrue);
    });

    test('when() evaluates an arbitrary deterministic predicate', () {
      final world = _world(DecisionFlow([]));
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'busy');
      world.flush();

      final policy = when(
        (c) => !c.has<OpenDecision>(),
      ).thenOpen(prompt: 'idle ping');
      final draft = policy.evaluate(
        DecisionContext(actor: actor, world: world, tick: 0),
      );
      expect(draft, isNull); // actor HAS OpenDecision — abstains
    });
  });

  group('flow evaluation', () {
    test('first non-null draft wins', () {
      final world = _world(DecisionFlow([]));
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.getEntity(actor).$1.insert(const ToolResultPendingMarker());
      world.flush();

      final flow = DecisionFlow([
        onToolResult().thenOpen(prompt: 'from-first'),
        onToolResult().thenOpen(prompt: 'from-second'),
      ]);
      final result = flow.evaluate(
        DecisionContext(actor: actor, world: world, tick: 0),
      );
      expect(result?.policyName, 'onToolResult');
      expect(result?.draft.prompt, 'from-first');
    });

    test('defaultReAct flow opens continuation on marker', () {
      final world = _world(DecisionFlow.defaultReAct());
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.getEntity(actor).$1.insert(const ToolResultPendingMarker());
      world.flush();

      final result = DecisionFlow.defaultReAct().evaluate(
        DecisionContext(actor: actor, world: world, tick: 0),
      );
      expect(result?.policyName, 'react_continuation');
    });
  });

  group('end-to-end application', () {
    test(
      'decisionFlowSystem opens attributed decisions and clears markers',
      () async {
        final world = _world(
          DecisionFlow([
            whenIdleEveryNTicks(2).thenOpen(prompt: 'tick decision'),
          ]),
        );
        final scene = spawnScene(world);
        final actor = spawnActor(world, scene);
        world.flush();

        // Advance the frame to tick 4 and run AgencyGrant.
        syncScheduleExecutionFrame(world, explicitFrameId: 4);
        world.flush();
        world.runSchedule(Schedules.agencyGrant);
        world.flush();

        final e = world.getEntity(actor).$1;
        expect(e.has<OpenDecision>(), isTrue);
        expect(e.get<DecisionOrigin>()?.policyName, 'everyNTicks(2)');
        expect(beatsWithText(world, 'tick decision'), hasLength(0));

        // Marker cleared after evaluation (none was set here, but the sweep
        // must not throw).
        expect(
          world.query2<Actor, ToolResultPendingMarker>().toList(),
          isEmpty,
        );
      },
    );

    test('custom flow routes tool results differently than default', () async {
      final jail = await Directory.systemTemp.createTemp('flow_e2e_');
      addTearDown(() => jail.delete(recursive: true));

      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(AgencyPolicy(maxConcurrent: 1))
        ..upsertResource(
          DecisionFlowResource(
            DecisionFlow([
              onToolResult().thenOpen(
                prompt: 'CUSTOM ROUTING: reflect on the tool output.',
              ),
            ]),
          ),
        )
        ..flush();

      var calls = 0;
      final prompts = <String>[];
      world.getResource<GenerationHandlerResource>().registerDefault(
        _WriteThenAnswer(prompts: prompts, calls: () => ++calls),
      );
      final registry = ToolRegistry()
        ..register(writeTool(FsToolsRoot(jail.path)));
      world.getResource<ToolRegistryResource>().register('default', registry);

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'go');
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      await HarnessLoop(world: world).runUntilIdle();

      // The custom prompt reached the model on the continuation turn —
      // proof that developer-authored flows route real decisions.
      expect(
        prompts.any((p) => p.contains('CUSTOM ROUTING')),
        isTrue,
        reason: 'the custom flow should have opened the continuation decision',
      );
      expect(calls, 2);
    });

    test('per-policy precision attribution', () async {
      final world = _world(
        DecisionFlow([whenIdleEveryNTicks(2).thenOpen(prompt: 'attributed')]),
      );
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      syncScheduleExecutionFrame(world, explicitFrameId: 6);
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();

      // Decision created but not yet answered → answered=0.
      final stats = decisionPrecisionByPolicy(world);
      expect(stats['everyNTicks(2)']?.created, 1);
      expect(stats['everyNTicks(2)']?.answered, 0);
    });
  });

  group('deferred thinking', () {
    test('thenDream stamps DeferredThinking on the decision', () async {
      final world = _world(
        DecisionFlow([whenIdleEveryNTicks(3).thenDream('dream')]),
      );
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      syncScheduleExecutionFrame(world, explicitFrameId: 3);
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();

      final e = world.getEntity(actor).$1;
      expect(e.has<DeferredThinking>(), isTrue);
      expect(e.get<OpenDecision>()?.prompt, 'dream');
    });
  });
}

class _WriteThenAnswer implements GenerationHandler {
  _WriteThenAnswer({required this.prompts, required this.calls});
  final List<String> prompts;
  final int Function() calls;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final n = calls();
    prompts.add(request.prompt);
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'step $n'},
      rawOutput: 'step $n',
      toolCalls: n == 1
          ? [
              ToolCall(
                name: ToolName('write'),
                arguments: {'path': 'out.txt', 'content': 'hi'},
              ),
            ]
          : const [],
      taskId: request.taskId,
    );
  }
}
