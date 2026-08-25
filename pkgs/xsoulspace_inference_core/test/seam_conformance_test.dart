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

Future<void> _cycle(World world) =>
    runCycle(world, settleDelay: const Duration(milliseconds: 30));

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

      // Field-level determinism on the pure evaluation path (the applied
      // OpenDecision above drops shareWith/deferredThinking): evaluating the
      // SAME flow twice against ONE unchanged world yields identical policy
      // names and draft fields (ADR 0007 §2 policy determinism).
      final world = await buildTestWorld(decisionFlow: flow);
      final actor = spawnActor(world, spawnScene(world));
      syncScheduleExecutionFrame(world, explicitFrameId: 9);
      world.flush();
      final first = flow.evaluate(
        DecisionContext(actor: actor, world: world, tick: 9),
      );
      final second = flow.evaluate(
        DecisionContext(actor: actor, world: world, tick: 9),
      );
      expect(first?.policyName, second?.policyName);
      expect(first?.draft.prompt, second?.draft.prompt);
      expect(first?.draft.priority, second?.draft.priority);
      expect(first?.draft.escalate, second?.draft.escalate);
      expect(first?.draft.deferredThinking, second?.draft.deferredThinking);
      expect(first?.draft.shareWith, second?.draft.shareWith);
      expect(first?.draft.prompt, 'identical');
    });

    test(
      'evaluating policies leaves the observed world surface untouched',
      () async {
        final flow = DecisionFlow([
          whenIdleEveryNTicks(3).thenOpen(prompt: 'pure'),
          onToolResult().thenOpen(prompt: 'continue'),
        ]);
        final world = await buildTestWorld(decisionFlow: flow);
        final actor = spawnActor(world, spawnScene(world));
        syncScheduleExecutionFrame(world, explicitFrameId: 12);
        world.flush();

        final before = _policySurfaceFingerprint(world);
        final first = flow.evaluate(
          DecisionContext(actor: actor, world: world, tick: 12),
        );
        final second = flow.evaluate(
          DecisionContext(actor: actor, world: world, tick: 12),
        );
        final after = _policySurfaceFingerprint(world);

        expect(
          first?.draft.prompt,
          second?.draft.prompt,
          reason: 'repeated evaluation is deterministic',
        );
        expect(
          after,
          before,
          reason:
              'purity canary: policy.evaluate must not insert/remove '
              'components or touch the facet index (ADR 0007 §2)',
        );
      },
    );
  });

  group('seam 2 — generation handler', () {
    test('fault matrix produces contracted recovery or timeout', () async {
      Future<(World, ScriptedGenerationHandler)> drive(
        List<ScriptedTurn> turns,
      ) async {
        final handler = ScriptedGenerationHandler(turns);
        return (await _worldFor(handler), handler);
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
        final world = await _worldFor(handler);
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
      hang.$1.getResource<AgencyPolicy>().taskTimeout = const Duration(
        milliseconds: 20,
      );
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
      // The scripted handler exhausts its turns, so the retry loop keeps the
      // final OpenDecision pending. The conformance claim is that timeout
      // recovery produced a real beat, not that a finite script is infinite.
    });
  });

  group('seam 3 — tools', () {
    test('timeout, throw, unknown tool, and serialization conform', () async {
      final world = await buildTestWorld();
      world.getResource<AgencyPolicy>().taskTimeout = const Duration(
        milliseconds: 20,
      );
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
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, scene);
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
              in world
                  .query3<ToolResultContent, BeatStatus, TextContent>()
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
      expect(hung.output, contains('Unknown tool'));

      final thrown = await call('thrower', {});
      expect(thrown.output, contains('tool exploded'));

      final payload = {
        'id': 'abc',
        'values': [1, 2.5, true],
      };
      final unknownRegistryResult = await ToolRegistry().execute(
        const ToolName('missing'),
        payload,
      );
      expect(unknownRegistryResult, isNotNull);
      expect(
        (jsonDecode(unknownRegistryResult!) as Map<String, dynamic>)['error'],
        contains('Unknown tool'),
      );

      final structured = await call('structured', payload);
      final structuredEvidence = [
        for (final (entity, result, _, _)
            in world
                .query3<ToolResultContent, BeatStatus, TextContent>()
                .toList())
          if (result.name == 'structured') entity,
      ];
      expect(structuredEvidence, hasLength(1));
      final structuredOutput = structuredEvidence.single
          .get<ToolResultContent>()!
          .output;
      final decodedStructured =
          jsonDecode(structuredOutput.toString()) as Map<String, dynamic>;
      expect(decodedStructured, {'received': payload, 'ok': true});
      expect(
        ToolExecutionResult.fromJson(structured.toJson()).output,
        structured.output,
      );
    });

    test('hung tool honors AgencyPolicy.taskTimeout', () async {
      final world = await buildTestWorld();
      world.getResource<AgencyPolicy>().taskTimeout = const Duration(
        milliseconds: 20,
      );
      world.upsertResource(
        ToolExecutorResource()..register(
          const ToolName('hang'),
          (_) => Completer<Object?>().future,
        ),
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
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      final taskId = TaskId.create();
      world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
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
      final timeoutOutput = evidence.single
          .get<ToolResultContent>()!
          .output
          .toString();
      expect(timeoutOutput, contains('TimeoutException'));
      world.getResource<TaskRegistryResource>().take(taskId);
    });

    test('nested unicode payloads round-trip losslessly into beats', () async {
      final world = await buildTestWorld();
      const payload = <String, dynamic>{
        'id': 'run-42',
        'labels': ['café', '日本語のテキスト', '🚀 launch'],
        'nested': {
          'values': [1, 2.5, true, false, null],
          'leaf': {'note': 'vàlue ✓'},
          'emptyList': <dynamic>[],
          'emptyMap': <String, dynamic>{},
        },
      };
      world.upsertResource(
        ToolExecutorResource()
          ..register(const ToolName('deep_echo'), (_) async => payload),
      );
      world.getResource<ToolRegistryResource>().register(
        'default',
        ToolRegistry()..register(
          ToolDef.encode(
            name: const ToolName('deep_echo'),
            description: 'echo nested payloads',
            execute: (_) async => payload,
          ),
        ),
      );
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      final taskId = TaskId.create();
      world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
      world.events.writer<ToolCallEvent>().send(
        ToolCallEvent(
          actorEntity: actor,
          call: const ToolCall(
            name: ToolName('deep_echo'),
            arguments: {'query': 'café ✓'},
          ),
          taskId: taskId,
        ),
      );
      world.runSchedule(Schedules.mechanical);
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      world.runSchedule(Schedules.mechanical);
      world.flush();

      final results = [
        for (final (entity, content)
            in world.query<ToolResultContent>().toList())
          if (content.name == 'deep_echo') entity,
      ];
      expect(results, hasLength(1), reason: 'deep_echo produced one beat');
      final content = results.single.get<ToolResultContent>()!;
      expect(content.output, isA<String>());
      final decoded =
          jsonDecode(content.output as String) as Map<String, dynamic>;
      expect(
        decoded,
        equals(payload),
        reason: 'map/list structure survives executor → event → beat',
      );
      expect((decoded['labels'] as List).join(), contains('🚀'));
      expect((decoded['labels'] as List).join(), contains('日本語'));
      expect((decoded['nested'] as Map)['leaf'], equals({'note': 'vàlue ✓'}));
      // The projection line keeps the full encoded payload verbatim.
      final resultBeat = beatsWithText(world, '<result|deep_echo|').single;
      final text = world.getEntity(resultBeat).$1.get<TextContent>()!.text;
      expect(text, contains('日本語のテキスト'));
      expectIdle(world);
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

    // ADR 0007 §2 asks for a runtime debug assertion on budget breach; the
    // actual contract today (projection_systems.dart fitToBudget) is SILENT
    // TRUNCATION: over-budget beats are dropped, `truncated` flips true, and
    // the green-screen absence names how much went off-screen. This test
    // documents that contract — no throw, no budget overrun.
    test('budget breach degrades by documented silent truncation', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 150));
      world.flush();
      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        systemPrompt: 'cache tuning agent',
        openDecisionPrompt: 'confirm lru eviction fix',
      );
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      addIndexedBeat(
        world,
        thread,
        actor,
        'telemetry shows lru thrash at peak',
        ['lru'],
      );
      addIndexedBeat(world, thread, actor, 'lru eviction swept cold entries', [
        'lru',
        'eviction',
      ]);
      addIndexedBeat(world, thread, actor, 'museum ' * 200, ['museum']);

      projectFor(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(
        situation.tokensUsed,
        lessThanOrEqualTo(situation.tokenBudget),
        reason: 'reported spend stays within the declared budget',
      );
      expect(situation.truncated, isTrue);
      expect(
        situation.explicitAbsences.join(' '),
        contains('off-screen'),
        reason: 'green screen names the pruned remainder',
      );
      final projected = [
        for (final beat in situation.projectedBeats) fragmentText(world, beat),
      ].join('\n');
      expect(projected, contains('lru thrash'));
      expect(projected, contains('swept cold entries'));
      expect(
        projected.contains('museum'),
        isFalse,
        reason: 'the oversized irrelevant beat is what gets pruned',
      );
      expect(
        situation.projectedBeats.length,
        lessThanOrEqualTo(ProjectionPolicy().maxBeats),
      );

      final actorEntity = world.getEntity(actor).$1;
      if (actorEntity.has<OpenDecision>()) actorEntity.remove<OpenDecision>();
      if (actorEntity.has<Agency>()) actorEntity.remove<Agency>();
      world.flush();
      expectIdle(world);
    });
  });

  group('A4 verifier-tool conformance — verify_step (seam 3 × seam 5)', () {
    test('passing verdict flips the linked step to verified', () async {
      final rig = await _verificationRig(
        (_) async => <String, dynamic>{'passed': true, 'failures': ''},
      );
      final status = await _driveMechanicalVerification(
        rig.$1,
        actor: rig.$2,
        step: rig.$4,
      );
      expect(status, StepLifecycle.verified);
      _drainVerificationState(rig.$1, rig.$2);
      expectIdle(rig.$1);
    });

    test('failing verdict teaches and flips the step to failed', () async {
      const teaching = 'artifact cafe missing from workspace evidence';
      Future<Object?> verify(Object? args) async => <String, dynamic>{
        'passed': false,
        'failures': teaching,
      };
      final rig = await _verificationRig(verify);
      final status = await _driveMechanicalVerification(
        rig.$1,
        actor: rig.$2,
        step: rig.$4,
      );
      expect(status, StepLifecycle.failed);
      // The teaching shape is reachable at the executor boundary — the
      // contract is structured data, never an exception.
      final out = await verify(const {'artifact': 'cafe'});
      expect(out, isA<Map>());
      expect((out! as Map)['passed'], isFalse);
      expect((out as Map)['failures'], teaching);
      _drainVerificationState(rig.$1, rig.$2);
      expectIdle(rig.$1);
    });

    test('throwing verifier leaves the step open, loop intact', () async {
      final rig = await _verificationRig(
        (_) async => throw StateError('verifier exploded'),
      );
      final status = await _driveMechanicalVerification(
        rig.$1,
        actor: rig.$2,
        step: rig.$4,
      );
      expect(
        status,
        StepLifecycle.open,
        reason: 'absence of proof is not failure',
      );
      _drainVerificationState(rig.$1, rig.$2);
      expectIdle(rig.$1);
    });

    test('missing verify_step executor leaves the step open', () async {
      final rig = await _verificationRig(null);
      final status = await _driveMechanicalVerification(
        rig.$1,
        actor: rig.$2,
        step: rig.$4,
      );
      expect(status, StepLifecycle.open);
      _drainVerificationState(rig.$1, rig.$2);
      expectIdle(rig.$1);
    });

    test('same workspace state yields the same verdict twice', () async {
      // A verifier must be a pure function of the observed state — no
      // clocks, no call counters. Identical probes get identical verdicts;
      // different state flips the verdict deterministically.
      Future<Object?> verify(Object? args) async {
        final map = args is Map ? args : const <String, dynamic>{};
        final present = map['artifact'] == 'cafe';
        return <String, dynamic>{
          'passed': present,
          'failures': present ? '' : 'artifact cafe missing from workspace',
        };
      }

      final first = await verify(const {'artifact': 'cafe'});
      final second = await verify(const {'artifact': 'cafe'});
      expect(first, second, reason: 'deterministic predicate, not a coin flip');
      expect((first! as Map)['passed'], isTrue);
      final third = await verify(const <String, dynamic>{});
      expect(third, isNot(equals(first)));
      expect((third! as Map)['passed'], isFalse);
    });

    test(
      'hung verify_step honors AgencyPolicy.taskTimeout on tool path',
      () async {
        final world = await buildTestWorld();
        world.getResource<AgencyPolicy>().taskTimeout = const Duration(
          milliseconds: 20,
        );
        world.upsertResource(
          ToolExecutorResource()..register(
            const ToolName('verify_step'),
            (_) => Completer<Object?>().future,
          ),
        );
        world.flush();
        final registry = ToolRegistry()
          ..register(
            ToolDef(
              name: const ToolName('verify_step'),
              description: 'mechanical acceptance predicate',
              execute: (_) => Completer<String>().future,
            ),
          );
        world.getResource<ToolRegistryResource>().register('default', registry);
        final scene = spawnScene(world);
        final actor = spawnActor(world, scene);
        world.upsertComponent(actor, const ActorTools(registryName: 'default'));
        final thread = spawnThread(world, actor, scene);
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
            call: const ToolCall(name: ToolName('verify_step'), arguments: {}),
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
          for (final (entity, content)
              in world.query<ToolResultContent>().toList())
            if (content.name == 'verify_step') entity,
        ];
        expect(
          evidence,
          hasLength(1),
          reason: 'timeout becomes durable result',
        );
        expect(
          evidence.single.get<ToolResultContent>()!.output.toString(),
          contains('TimeoutException'),
        );
        world.getResource<TaskRegistryResource>().take(taskId);
      },
    );
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
          return '{"passed":true,"exitCode":0}';
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
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      world.flush();

      final taskId = TaskId.create();
      world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
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
      world.runSchedule(Schedules.processResponses);
      world.flush();
      world.runSchedule(Schedules.mechanical);
      world.flush();

      expect(calls, 1);
      final evidence = [
        for (final (entity, result)
            in world.query<ToolResultContent>().toList())
          if (result.name == 'run_tests') entity,
      ];
      expect(
        evidence,
        hasLength(1),
        reason: 'verifier output becomes durable graph evidence',
      );
      final stepFacade = world.getEntity(step).$1;
      expect(stepFacade.get<Step>()!.status, StepLifecycle.open);
      final updatedStep = Step(
        claim: 'tests pass',
        verificationKind: StepVerificationKind.mechanical,
        status: StepLifecycle.verified,
      );
      world.upsertComponent(step, updatedStep);
      world.flush();
      final projection = projectPlanFrontier(
        world,
        step,
        budget: 1000,
        estimator: defaultTokenEstimator,
      );
      // Verified steps leave the frontier; only open work is projected.
      expect(projection.steps, isEmpty);
    });
  });
}

Future<World> _worldFor(GenerationHandler handler) async {
  final world = await buildTestWorld(
    handler: handler,
    agencyPolicy: AgencyPolicy(taskTimeout: const Duration(minutes: 5)),
  );
  spawnActor(world, spawnScene(world), openDecisionPrompt: 'go');
  world.flush();
  return world;
}

Future<Object?> _evaluateFlow(DecisionFlow flow, {required int frameId}) async {
  final world = await buildTestWorld(decisionFlow: flow);
  final scene = spawnScene(world);
  spawnActor(world, scene);
  syncScheduleExecutionFrame(world, explicitFrameId: frameId);
  world.flush();
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  return world.query2<Actor, OpenDecision>().single.$2;
}

/// Stable snapshot of every component surface a [DecisionContext] can
/// observe — the actor's components, co-present actors, all beats — plus the
/// derived facet index and in-flight tasks. Policy purity (ADR 0007 §2)
/// means this map is identical before and after `evaluate`.
Map<String, Object?> _policySurfaceFingerprint(World world) {
  final rows = <String>[
    for (final (e, c) in world.query<Actor>().toList()) '$e|${c.agentId}',
    for (final (e, c) in world.query<ActorModel>().toList()) '$e|${c.modelId}',
    for (final (e, c) in world.query<ActorSystemPrompt>().toList())
      '$e|${c.text}',
    for (final (e, c) in world.query<ActorTools>().toList())
      '$e|${c.registryName}',
    for (final (e, c) in world.query<ActorThreads>().toList())
      '$e|${c.threads.join(",")}',
    for (final (e, _) in world.query<Agency>().toList()) '$e|agency',
    for (final (e, _) in world.query<AwaitingResponse>().toList())
      '$e|awaiting',
    for (final (e, c) in world.query<OpenDecision>().toList())
      '$e|${c.prompt}|${c.priority}|${c.escalate}',
    for (final (e, _) in world.query<EscalationRequest>().toList())
      '$e|escalation',
    for (final (e, c) in world.query<PresentInScene>().toList())
      '$e|${c.sceneEntity}',
    for (final (e, c) in world.query<Goal>().toList()) '$e|${c.text}',
    for (final (e, c) in world.query<RetryCount>().toList()) '$e|${c.value}',
    for (final (e, c) in world.query<ToolRoundCount>().toList())
      '$e|${c.value}',
    for (final (e, c) in world.query<DecisionOrigin>().toList())
      '$e|${c.policyName}',
    for (final (e, _) in world.query<DeferredThinking>().toList())
      '$e|deferred',
    for (final (e, _) in world.query<ToolResultPendingMarker>().toList())
      '$e|pending',
    for (final (e, c) in world.query<TextContent>().toList()) '$e|${c.text}',
  ]..sort();
  final index = world.getResource<FacetIndex>();
  final keywords = <String>[
    for (final entry in index.byKeyword.entries)
      for (final beat in entry.value) '${entry.key}->$beat',
  ]..sort();
  return <String, Object?>{
    'components': rows,
    'facetKeywords': keywords,
    'tasks': world.getResource<TaskRegistryResource>().length,
  };
}

/// Spawn the minimal mechanical-verification rig: an idle actor bound to a
/// (possibly empty) default registry plus one open mechanical [Step] whose
/// `criterionArgs` travel to the `verify_step` executor.
Future<(World, Entity, Entity, Entity)> _verificationRig(
  Future<Object?> Function(Object? args)? verify,
) async {
  final world = await buildTestWorld();
  if (verify != null) {
    world.upsertResource(
      ToolExecutorResource()..register(const ToolName('verify_step'), verify),
    );
  }
  world.getResource<ToolRegistryResource>().register('default', ToolRegistry());
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene);
  world.upsertComponent(actor, const ActorTools(registryName: 'default'));
  final thread = spawnThread(world, actor, scene);
  world.upsertComponent(actor, ActorThreads(threads: [thread]));
  final step = world.spawnComponents([
    Step(
      claim: 'artifact published',
      verificationKind: StepVerificationKind.mechanical,
      criterionArgs: const {'artifact': 'cafe'},
    ),
  ]);
  world.flush();
  return (world, actor, thread, step);
}

/// Drive the mechanical verification window deterministically:
///
/// 1. Land one tool result while the actor holds NO decision so
///    `processToolResultsSystem` stamps the ReAct continuation marker.
/// 2. Re-open a host decision carrying the plan-step backlink BEFORE any
///    AgencyGrant pass clears the marker — the exact window
///    `verifyStepSystem` runs its acceptance predicate in.
///
/// Returns the step's lifecycle after the verifier ran.
Future<StepLifecycle> _driveMechanicalVerification(
  World world, {
  required Entity actor,
  required Entity step,
}) async {
  final taskId = TaskId.create();
  world.getResource<TaskRegistryResource>().register(taskId, TaskHandle());
  world.events.writer<ToolCallEvent>().send(
    ToolCallEvent(
      actorEntity: actor,
      call: const ToolCall(name: ToolName('run_probe'), arguments: {}),
      taskId: taskId,
    ),
  );
  world.runSchedule(Schedules.mechanical);
  world.flush();
  await Future<void>.delayed(const Duration(milliseconds: 30));
  world.runSchedule(Schedules.mechanical);
  world.flush();

  expect(
    world.getEntity(actor).$1.has<ToolResultPendingMarker>(),
    isTrue,
    reason: 'landed tool result must arm the continuation marker',
  );
  world.upsertComponent(
    actor,
    OpenDecision(prompt: 'close out the step', stepId: step),
  );
  world.flush();
  world.runSchedule(Schedules.mechanical);
  // verifyStepSystem awaits the executor; let its continuation land.
  await Future<void>.delayed(Duration.zero);
  world.flush();
  return world.getEntity(step).$1.get<Step>()!.status;
}

/// Remove test-injected decision/marker state so [expectIdle] reflects only
/// harness-owned work.
void _drainVerificationState(World world, Entity actor) {
  final entity = world.getEntity(actor).$1;
  if (entity.has<OpenDecision>()) entity.remove<OpenDecision>();
  if (entity.has<Agency>()) entity.remove<Agency>();
  if (entity.has<ToolResultPendingMarker>()) {
    entity.remove<ToolResultPendingMarker>();
  }
  if (entity.has<Situation>()) entity.remove<Situation>();
  world.flush();
}
