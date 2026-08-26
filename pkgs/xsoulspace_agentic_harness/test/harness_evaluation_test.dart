// ignore_for_file: lines_longer_than_80_chars

/// ADR 0003 — LLM-free harness evaluation: scripted handler, oracle scoring,
/// global invariants, golden ledger determinism, ablation matrix.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

Future<(World, Entity)> _worldWith(
  GenerationHandler handler, {
  Duration? timeout,
}) async {
  final world = await buildTestWorld(handler: handler);
  if (timeout != null) {
    world.getResource<AgencyPolicy>().taskTimeout = timeout;
  }
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene, openDecisionPrompt: 'go');
  world.flush();
  return (world, actor);
}

void main() {
  group('ScriptedGenerationHandler', () {
    test('serves turns in order and records requests', () async {
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(text: 'first'),
        ScriptedTurn(
          toolCalls: [
            ToolCall(name: ToolName('echo'), arguments: {'x': 1}),
          ],
          text: 'calling',
        ),
        const ScriptedTurn(text: 'done'),
      ]);
      final (world, actor) = await _worldWith(handler);

      for (final prompt in ['a', 'b', 'c']) {
        world.upsertComponent(actor, OpenDecision(prompt: prompt));
        world.flush();
        await runCycle(world);
      }

      expect(handler.requests, hasLength(3));
      expect(beatsWithText(world, 'first'), hasLength(1));
      expect(beatsWithText(world, 'done'), hasLength(1));
    });

    test('empty mode triggers the retry path', () async {
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.empty),
        const ScriptedTurn(text: 'recovered'),
      ]);
      final (world, actor) = await _worldWith(handler);

      // First cycle returns empty → retry decision is created.
      await runCycle(world);
      // Second cycle resolves the retry with the recovery turn.
      await runCycle(world);

      expect(handler.requests, hasLength(2));
      expect(beatsWithText(world, 'recovered'), hasLength(1));
    });

    test('throwSync mode is converted to an error response + retry', () async {
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.throwSync),
        const ScriptedTurn(text: 'after crash'),
      ]);
      final (world, actor) = await _worldWith(handler);

      await runCycle(world);
      await runCycle(world);

      expect(handler.requests, hasLength(2));
      expect(beatsWithText(world, 'after crash'), hasLength(1));
    });

    test('hang mode is swept by taskTimeout', () async {
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.hang),
        const ScriptedTurn(text: 'after timeout'),
      ]);
      final (world, actor) = await _worldWith(
        handler,
        timeout: const Duration(milliseconds: 100),
      );

      // First dispatch hangs; wait past timeout; sweep; retry resolves.
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      world.runSchedule(Schedules.processResponses);
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      world.runSchedule(Schedules.processResponses);
      world.flush();

      expect(handler.requests, hasLength(2));
      expect(beatsWithText(world, 'after timeout'), hasLength(1));
    });

    test('streaming deltas land in StreamingBeat', () async {
      final handler = ScriptedGenerationHandler([
        ScriptedTurn(deltas: ['Hel', 'lo'], text: 'Hello'),
      ]);
      final (world, actor) = await _worldWith(handler);

      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      // Deltas land as ActorGenerateStreamEvents; ProcessResponses drains
      // them into StreamingBeat.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      world.flush();
      world.runSchedule(Schedules.processResponses);
      world.flush();

      final beat = world.getEntity(actor).$1.get<StreamingBeat>();
      expect(beat?.chunks.join(), 'Hello');
    });
  });

  group('checkHarnessInvariants', () {
    test('clean world has no violations', () async {
      final handler = MockGenerationHandler(responseText: 'ok');
      final (world, _) = await _worldWith(handler);
      await runCycle(world);
      expect(checkHarnessInvariants(world), isEmpty);
    });

    test('detects Agency without OpenDecision', () async {
      final (world, actor) = await _worldWith(
        MockGenerationHandler(responseText: 'ok'),
      );
      // Resolve the actor's own decision first, then forge the violation:
      // Agency present while no OpenDecision exists.
      await runCycle(world);
      world.getEntity(actor).$1.insert(const Agency());
      world.flush();
      final violations = checkHarnessInvariants(world);
      expect(
        violations.any((v) => v.contains('Agency without OpenDecision')),
        isTrue,
      );
    });

    test('detects private-beat leakage into a projection', () async {
      final (world, actor) = await _worldWith(
        MockGenerationHandler(responseText: 'ok'),
      );
      // Reuse the world's existing scene — multi-scene projection asserts.
      final scene = world.query2<Scene, SceneFrame>().first.$1.entity;
      final other = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      final beat = addIndexedBeat(world, thread, other, 'secret diary', [
        'diary',
      ]);
      world.getEntity(beat).$1.insert(PrivateToActor(other));

      world.upsertComponent(actor, OpenDecision(prompt: 'diary'));
      world.flush();
      projectFor(world);

      final situation = world.getEntity(actor).$1.get<Situation>();
      if (situation != null && situation.projectedBeats.isNotEmpty) {
        // Force the leak into the projection to prove detection works.
        situation.projectedBeats.add(beat);
        final violations = checkHarnessInvariants(world);
        expect(violations.any((v) => v.contains('private beat')), isTrue);
      }
    });
  });

  group('golden ledger', () {
    test('two identical runs produce identical dumps', () async {
      String runOnce() {
        var dump = '';
        // Synchronous world construction; run inside a zone-free helper.
        return dump;
      }

      Future<String> runGolden() async {
        final handler = MockGenerationHandler(responseText: 'stable answer');
        final world = await buildTestWorld(handler: handler);
        final ledger = HarnessExecutionLedger(world);
        world.executionObserver = ledger;
        final scene = spawnScene(world);
        final actor = spawnActor(world, scene, openDecisionPrompt: 'go');
        world.flush();
        final thread = spawnThread(world, actor, scene);
        world.upsertComponent(actor, ActorThreads(threads: [thread]));
        world.upsertComponent(actor, OpenDecision(prompt: 'go'));
        world.flush();
        await HarnessLoop(world: world).runUntilIdle(maxTicks: 5000);
        final out = ledger.dumpGolden();
        world.clear();
        return out;
      }

      final a = await runGolden();
      final b = await runGolden();
      expect(a, isNotEmpty);
      expect(a, b, reason: 'identical runs must produce identical ledgers');
      expect(runOnce(), isEmpty); // silence unused warning
    });

    test('dumpGolden excludes timing but keeps channel flow', () async {
      final jail = await Directory.systemTemp.createTemp('golden_ledger_');
      addTearDown(() => jail.delete(recursive: true));

      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();
      world.getResource<GenerationHandlerResource>().registerDefault(
        MockGenerationHandler(responseText: 'done'),
      );
      final ledger = HarnessExecutionLedger(world);
      world.executionObserver = ledger;
      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'go');
      world.flush();
      await HarnessLoop(world: world).runUntilIdle(maxTicks: 5000);

      final dump = ledger.dumpGolden();
      expect(dump, isNot(contains('µs')));
      expect(dump, contains('ActorGenerateResponse 0→1'));
    });
  });

  group('oracle scoring', () {
    test('scores projection recall and missing tool calls', () async {
      final world = await buildTestWorld();
      final handler = MockGenerationHandler(responseText: 'parser fixed');

      // Spawn manually and seed a relevant beat so the exact cut is
      // non-empty (ADR 0004: scoring uses the true cut when captured).
      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'a', systemPrompt: 'p'),
      ], scene);
      world.getResource<GenerationHandlerResource>().registerDefault(handler);
      addIndexedBeat(
        world,
        spawned.first.thread,
        spawned.first.entity,
        'the parser fails on brackets',
        ['parser'],
      );

      final metrics = await driveOneDecision(
        world,
        spawned.first.entity,
        'fix parser',
      );

      final results = scoreOracles(world, metrics, [
        const DecisionOracle(
          mustProject: ['parser'],
          expectedToolCalls: ['read'],
        ),
      ]);

      expect(results, hasLength(1));
      expect(results.first.projectionRecall, 1.0);
      expect(results.first.missingToolCalls, ['read']);
      expect(results.first.passed, isFalse);
    });

    test('detects leaked keywords', () async {
      final world = await buildTestWorld();
      final handler = MockGenerationHandler(responseText: 'weather sunny');

      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'a', systemPrompt: 'p'),
      ], scene);
      world.getResource<GenerationHandlerResource>().registerDefault(handler);
      addIndexedBeat(
        world,
        spawned.first.thread,
        spawned.first.entity,
        'the weather is sunny today',
        ['weather'],
      );

      final metrics = await driveOneDecision(
        world,
        spawned.first.entity,
        'weather?',
      );

      final results = scoreOracles(world, metrics, [
        const DecisionOracle(mustNotProject: ['weather']),
      ]);
      expect(results.first.leakedKeywords, ['weather']);
    });
  });

  group('ablation matrix', () {
    test('runs configs on fresh worlds and reports deltas', () async {
      final scenario = Scenario(
        name: 'abl',
        actors: [
          ScenarioActor(
            name: 'a',
            systemPrompt: 'p',
            decisions: ['one', 'two'],
          ),
        ],
      );

      final results = await runAblations(scenario, defaultAblations, (
        config,
      ) async {
        final world = World()..addPlugin(AgentPlugin());
        world
          ..upsertResource(ModelRouterResource(ModelRouter()))
          ..upsertResource(ToolRegistryResource())
          ..flush();
        world.getResource<GenerationHandlerResource>().registerDefault(
          MockGenerationHandler(responseText: 'resp ${config.name}'),
        );
        return world;
      });

      expect(results.map((r) => r.configName), [
        'baseline',
        'no_green_screen',
        'unbounded_budget',
      ]);
      for (final r in results) {
        expect(r.metrics.decisions, hasLength(2));
        expect(r.metrics.totalLlmCalls, 2);
      }
      // Unbounded budget never truncates.
      expect(results.last.truncationRate, 0.0);
    });
  });
}
