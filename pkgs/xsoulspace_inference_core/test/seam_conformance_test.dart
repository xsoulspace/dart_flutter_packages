// ignore_for_file: lines_longer_than_80_chars

/// ADR 0007 §2 — deterministic conformance suites for the five extension
/// seams: decide, act, touch world, see, and mechanical verification.
library;

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

Future<void> _cycle(World world) async {
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  world.runSchedule(Schedules.project);
  world.flush();
  await world.runScheduleAsync(Schedules.actorAct);
  world.flush();
  await Future<void>.delayed(const Duration(milliseconds: 30));
  world.runSchedule(Schedules.processResponses);
  world.flush();
  world.runSchedule(Schedules.mechanical);
  world.flush();
}

void main() {
  group('seam 1 — decision policy', () {
    test('same fixture state produces an identical draft', () async {
      final flow = DecisionFlow([
        whenIdleEveryNTicks(3).thenOpen(prompt: 'identical'),
      ]);

      final drafts = await Future.wait([
        _evaluateFlow(flow, frameId: 9),
        _evaluateFlow(flow, frameId: 9),
      ]);

      expect(drafts[0].runtimeType, drafts[1].runtimeType);
      expect(
        drafts[0].toString(),
        drafts[1].toString(),
        reason: 'policy must be a pure function of fixture state',
      );
      expect(drafts[0], isNotNull);
    });
  });

  group('seam 2 — generation handler', () {
    test('fault matrix produces contracted recovery or timeout', () async {
      Future<(World, ScriptedGenerationHandler)> drive(
        List<ScriptedTurn> turns,
      ) async {
        final handler = ScriptedGenerationHandler(turns);
        return (_worldFor(handler), handler);
      }

      final recoveryCases = [
        (ScriptedTurnMode.empty, 'empty recovered'),
        (ScriptedTurnMode.error, 'error recovered'),
        (ScriptedTurnMode.throwSync, 'crash recovered'),
      ];
      for (final (mode, recovered) in recoveryCases) {
        final handler = ScriptedGenerationHandler([
          ScriptedTurn(mode: mode),
          ScriptedTurn(text: recovered),
        ]);
        final world = _worldFor(handler);
        await _cycle(world);
        await _cycle(world);
        expect(handler.requests, hasLength(2), reason: '$mode');
        expect(beatsWithText(world, recovered), hasLength(1), reason: '$mode');
        expectIdle(world);
      }

      final hang = await drive([
        const ScriptedTurn(mode: ScriptedTurnMode.hang),
        const ScriptedTurn(text: 'timeout recovered'),
      ]);
      hang.$1.getResource<AgencyPolicy>().taskTimeout =
          const Duration(milliseconds: 20);
      await _cycle(hang.$1);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _cycle(hang.$1);
      await _cycle(hang.$1);
      await _cycle(hang.$1);
      expect(
        beatsWithText(hang.$1, 'timeout recovered'),
        isNotEmpty,
        reason: 'hang',
      );
      expectIdle(hang.$1);
    });
  });

  group('seam 3 — tools', () {
    test('timeout, throw, unknown tool, and serialization conform', () async {
      final world = await buildTestWorld();
      world.getResource<AgencyPolicy>().taskTimeout =
          const Duration(milliseconds: 20);
      world.upsertResource(
        ToolExecutorResource()
          ..register(const ToolName('hang'), (_) => Completer<Object?>().future)
          ..register(
            const ToolName('thrower'),
            (_) => throw StateError('tool exploded'),
          )
          ..register(
            const ToolName('structured'),
            (args) async => {'received': args, 'ok': true},
          ),
      );
      world.flush();

      final registry = ToolRegistry()
        ..register(
          ToolDef.encode(
            name: const ToolName('structured'),
            description: 'round trip',
            execute: (args) async => {'echo': args},
          ),
        );
      world.getResource<ToolRegistryResource>().register('default', registry);
      final actor = spawnActor(world, spawnScene(world));
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, spawnScene(world));
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      Future<ToolExecutionResult> call(
        String name,
        Map<String, dynamic> args,
      ) async {
        final taskId = TaskId.create();
        world.getResource<TaskRegistryResource>().register(
          taskId,
          TaskHandle(),
        );
        world.events.writer<ToolCallEvent>().send(
          ToolCallEvent(
            actorEntity: actor,
            call: ToolCall(name: ToolName(name), arguments: args),
            taskId: taskId,
          ),
        );
        world.runSchedule(Schedules.mechanical);
        world.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await Future<void>.delayed(const Duration(milliseconds: 40));
        world.runSchedule(Schedules.mechanical);
        world.flush();
        final evidence = [
          for (final (entity, result, _, _)
              in world.query3<ToolResultContent, BeatStatus, TextContent>()
                  .toList())
            if (result.name == name) entity,
        ];
        expect(evidence, hasLength(1), reason: 'tool $name produced evidence');
        return ToolExecutionResult(
          name: name,
          output: evidence.single.get<ToolResultContent>()!.output?.toString(),
        );
      }

      final hung = await call('missing_tool', {});
      expect(
        hung.output,
        contains('Unknown tool'),
      );

      final thrown = await call('thrower', {});
      expect(thrown.output, contains('tool exploded'));

      final payload = {'id': 'abc', 'values': [1, 2.5, true]};
      final unknownRegistryResult = await ToolRegistry().execute(
        const ToolName('missing'),
        payload,
      );
      expect(unknownRegistryResult, isNotNull);
      expect(
        jsonDecode(unknownRegistryResult!)['error'],
        contains('Unknown tool'),
      );

      final structured = await call('structured', payload);
      final structuredEvidence = [
        for (final (entity, result, _, _)
            in world.query3<ToolResultContent, BeatStatus, TextContent>()
                .toList())
          if (result.name == 'structured') entity,
      ];
      expect(structuredEvidence, hasLength(1));
      final structuredOutput =
          structuredEvidence.single.get<ToolResultContent>()!.output;
      final decodedStructured =
          jsonDecode(structuredOutput.toString()) as Map<String, dynamic>;
      expect(
        decodedStructured,
        {'received': payload, 'ok': true},
      );
      expect(
        ToolExecutionResult.fromJson(structured.toJson()).output,
        structured.output,
      );
    });

    test('hung tool honors AgencyPolicy.taskTimeout', () async {
      final world = await buildTestWorld();
      world.getResource<AgencyPolicy>().taskTimeout =
          const Duration(milliseconds: 20);
      world.upsertResource(
        ToolExecutorResource()
          ..register(const ToolName('hang'), (_) => Completer<Object?>().future),
      );
      world.flush();
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('hang'),
            description: 'hangs',
            execute: (_) => Completer<String>().future,
          ),
        );
      world.getResource<ToolRegistryResource>().register('default', registry);
      final actor = spawnActor(world, spawnScene(world));
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, spawnScene(world));
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      final taskId = TaskId.create();
      world.getResource<TaskRegistryResource>().register(
        taskId,
        TaskHandle(),
      );
      world.events.writer<ToolCallEvent>().send(
        ToolCallEvent(
          actorEntity: actor,
          call: const ToolCall(name: ToolName('hang'), arguments: {}),
          taskId: taskId,
        ),
      );
      world.runSchedule(Schedules.mechanical);
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      world.runSchedule(Schedules.mechanical);
      world.flush();

      final evidence = [
        for (final (entity, result, _)
            in world.query2<ToolResultContent, BeatStatus>().toList())
          if (result.name == 'hang') entity,
      ];
      expect(evidence, hasLength(1), reason: 'timeout becomes durable result');
      final timeoutOutput =
          evidence.single.get<ToolResultContent>()!.output.toString();
      expect(
        timeoutOutput,
        contains('TimeoutException'),
      );
      world.getResource<TaskRegistryResource>().take(taskId);
    });
  });

  group('seam 4 — projection', () {
    test('projection never exceeds its declared token budget', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 25));
      world.flush();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'budget');
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      addIndexedBeat(world, thread, actor, 'short relevant beat', ['short']);
      addIndexedBeat(world, thread, actor, 'z' * 400, ['long']);
      projectFor(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.tokensUsed, lessThanOrEqualTo(situation.tokenBudget));
      expect(situation.truncated, isTrue);
    });

    test('plan frontier respects budget and verifier lifecycle', () {
      final world = World()..addPlugin(AgentPlugin());
      world.flush();

      final verified = world.spawnComponents([
        Step(
          claim: 'verified dependency',
          verificationKind: StepVerificationKind.mechanical,
          status: StepLifecycle.verified,
        ),
      ]);
      final frontier = world.spawnComponents([
        DependsOnStep([verified]),
        Step(
          claim: 'mechanical frontier',
          verificationKind: StepVerificationKind.mechanical,
        ),
      ]);
      final blocked = world.spawnComponents([
        GoalLink(null),
        Step(claim: 'blocked', status: StepLifecycle.blocked),
      ]);
      world.flush();

      final projection = projectPlanFrontier(
        world,
        frontier,
        budget: defaultTokenEstimator('mechanical frontier'),
        estimator: defaultTokenEstimator,
      );

      expect(projection.steps, [frontier]);
      expect(projection.tokensUsed, lessThanOrEqualTo(projection.tokenBudget));
      expect(projection.truncated, isFalse);

      final all = projectPlanFrontier(
        world,
        null,
        budget: 10_000,
        estimator: defaultTokenEstimator,
      );
      expect(all.tokensUsed, lessThanOrEqualTo(all.tokenBudget));
      expect(all.steps, isNot(contains(blocked)));
    });
  });

  group('A2 verifier-tool seam', () {
    test('mechanical step only advances through verified evidence', () async {
      final handler = MockGenerationHandler(responseText: 'evidence');
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'verify');
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      final goal = world.spawnComponents([Goal(text: 'ship')]);
      final step = world.spawnComponents([
        GoalLink(goal),
        Step(
          claim: 'tests pass',
          verificationKind: StepVerificationKind.mechanical,
        ),
      ]);
      world.flush();

      var calls = 0;
      final executorResource = ToolExecutorResource()
        ..register(const ToolName('run_tests'), (_) async {
          calls++;
          return {'passed': true, 'exitCode': 0};
        });
      world.upsertResource(executorResource);
      final registry = ToolRegistry()
        ..register(
          ToolDef.encode(
            name: const ToolName('run_tests'),
            description: 'verifier',
            execute: (_) async => {'passed': true, 'exitCode': 0},
          ),
        );
      world.getResource<ToolRegistryResource>().register('default', registry);
      world.upsertComponent(actor, ActorTools(registryName: 'default'));
      world.flush();

      final taskId = TaskId.create();
      world.getResource<TaskRegistryResource>().register(
        taskId,
        TaskHandle(),
      );
      world.events.writer<ToolCallEvent>().send(
        ToolCallEvent(
          actorEntity: actor,
          call: const ToolCall(name: ToolName('run_tests'), arguments: {}),
          taskId: taskId,
        ),
      );
      world.runSchedule(Schedules.mechanical);
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      world.runSchedule(Schedules.mechanical);
      world.flush();

      expect(calls, 1);
      final evidence = [
        for (final (entity, result, _, _)
            in world.query3<ToolResultContent, BeatStatus, TextContent>()
                .toList())
          if (result.name == 'run_tests') entity,
      ];
      expect(
        evidence,
        hasLength(1),
        reason: 'verifier output becomes durable graph evidence',
      );
      final stepFacade = world.getEntity(step).$1;
      expect(stepFacade.get<Step>()!.status, StepLifecycle.open);
      stepFacade.get<Step>()!.status = StepLifecycle.verified;
      world.flush();
      final projection = projectPlanFrontier(
        world,
        null,
        budget: 1000,
        estimator: defaultTokenEstimator,
      );
      expect(projection.steps, [step]);
    });
  });
}

World _worldFor(GenerationHandler handler) {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(AgencyPolicy(taskTimeout: const Duration(minutes: 5)))
    ..flush();
  world.getResource<GenerationHandlerResource>().registerDefault(handler);
  spawnActor(world, spawnScene(world), openDecisionPrompt: 'go');
  world.flush();
  return world;
}

Future<Object?> _evaluateFlow(DecisionFlow flow, {required int frameId}) async {
  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource())
    ..upsertResource(DecisionFlowResource(flow))
    ..flush();
  final scene = spawnScene(world);
  spawnActor(world, scene);
  syncScheduleExecutionFrame(world, explicitFrameId: frameId);
  world.flush();
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  return world.query2<Actor, OpenDecision>().single.$2;
}
