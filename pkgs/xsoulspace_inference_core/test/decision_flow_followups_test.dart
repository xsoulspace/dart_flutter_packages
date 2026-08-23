// ignore_for_file: lines_longer_than_80_chars

/// ADR 0005 follow-ups: per-policy precision in ScenarioMetrics, shareWith
/// beat writes, and DeferredThinking projection expansion.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

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

/// Advance the harness tick to [tick] and run AgencyGrant
/// (decisionFlow + grant). Uses the real tick source
/// (ScheduleExecutionPolicyResource.frameId) that HarnessLoop advances.
void _grantAt(World world, int tick) {
  syncScheduleExecutionFrame(world, explicitFrameId: tick);
  world.flush();
  world.runSchedule(Schedules.agencyGrant);
  world.flush();
}

void main() {
  group('shareWith', () {
    test(
      'shared decision lands as an addressed beat in the target thread',
      () async {
        final teammate = AgentId('teammate-1');
        final world = _world(
          DecisionFlow([
            everyNTicks(
              2,
            ).thenOpen(prompt: 'Status sync needed', shareWith: [teammate]),
          ]),
        );
        final scene = spawnScene(world);
        final leader = spawnActor(world, scene);
        final helper = spawnActor(world, scene);
        // Give the target a thread so the shared beat has somewhere to land.
        final helperThread = spawnThread(world, helper, scene);
        world.upsertComponent(helper, ActorThreads(threads: [helperThread]));
        world.flush();

        _grantAt(world, 2);

        // The originator got the decision; the target got a shared beat.
        expect(world.getEntity(leader).$1.has<OpenDecision>(), isTrue);
        final sharedBeats = beatsWithText(world, 'Shared decision from a peer');
        expect(sharedBeats, isNotEmpty);
        final be = world.getEntity(sharedBeats.first).$1;
        expect(be.get<AddressedTo>()?.actor, helper);
        expect(be.get<BelongsToThread>()?.thread, helperThread);

        // And it is indexed — projection can ray-trace it later.
        expect(
          world.getResource<FacetIndex>().beatsFor(const ['sync']),
          isNotEmpty,
        );
      },
    );

    test('unknown target agent id is silently skipped', () async {
      final world = _world(
        DecisionFlow([
          everyNTicks(2).thenOpen(
            prompt: 'nobody home',
            shareWith: [const AgentId('ghost')],
          ),
        ]),
      );
      spawnScene(world);
      spawnActor(world, world.query2<Scene, SceneFrame>().first.$1.entity);
      world.flush();

      _grantAt(world, 2);
      expect(beatsWithText(world, 'Shared decision'), isEmpty);
    });
  });

  group('DeferredThinking projection expansion', () {
    test('dream turns project more beats than normal turns', () async {
      final world = _world(
        DecisionFlow([everyNTicks(3).thenDream('reflect deeply')]),
      );
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      // Seed many beats so the cap is the binding constraint. Default
      // maxBeats is 8; dream doubles to 16.
      for (var i = 0; i < 12; i++) {
        addIndexedBeat(world, thread, actor, 'note number $i', ['note$i']);
      }
      world.flush();

      // Normal turn: cap at 8 projected beats.
      world.upsertComponent(actor, OpenDecision(prompt: 'normal question'));
      world.flush();
      projectFor(world);
      final normal = world.getEntity(actor).$1.get<Situation>();
      expect(normal!.projectedBeats.length, lessThanOrEqualTo(8));

      // Dream turn: expanded cut projects more.
      world.getEntity(actor).$1.remove<OpenDecision>();
      world.getEntity(actor).$1.insert(const DeferredThinking());
      world.upsertComponent(actor, OpenDecision(prompt: 'dream question'));
      world.flush();
      projectFor(world);
      final dream = world.getEntity(actor).$1.get<Situation>();
      expect(
        dream!.projectedBeats.length,
        greaterThan(normal.projectedBeats.length),
        reason: 'deferred thinking must expand the cinematic cut',
      );
    });
  });

  group('policy precision in ScenarioMetrics', () {
    test('ScenarioRunner reports per-policy precision', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(
          DecisionFlowResource(
            DecisionFlow([everyNTicks(2).thenOpen(prompt: 'tick decision')]),
          ),
        )
        ..flush();

      final handler = MockGenerationHandler(responseText: 'done');
      final runner = ScenarioRunner(world: world, handler: handler);
      final metrics = await runner.run(
        Scenario(
          name: 'precision',
          actors: [
            ScenarioActor(name: 'a', systemPrompt: 'p', decisions: ['go']),
          ],
        ),
      );

      // The scenario's own decision was host-injected (no origin), but the
      // flow fired during AgencyGrant passes — attribution must exist and
      // the rate must be computable.
      expect(metrics.policyPrecision, isNotEmpty);
      expect(
        metrics.policyPrecision['everyNTicks(2)']?.created,
        greaterThanOrEqualTo(1),
      );
      expect(metrics.policyPrecisionRate['everyNTicks(2)'], isA<double>());
    });

    test(
      'runs without DecisionFlow decisions report empty precision',
      () async {
        final world = World()..addPlugin(AgentPlugin());
        world
          ..upsertResource(ModelRouterResource(ModelRouter()))
          ..upsertResource(ToolRegistryResource())
          ..upsertResource(DecisionFlowResource(DecisionFlow([])))
          ..flush();

        final handler = MockGenerationHandler(responseText: 'ok');
        final runner = ScenarioRunner(world: world, handler: handler);
        final metrics = await runner.run(
          Scenario(
            name: 'no-flow',
            actors: [
              ScenarioActor(name: 'a', systemPrompt: 'p', decisions: ['go']),
            ],
          ),
        );
        expect(metrics.policyPrecision, isEmpty);
      },
    );
  });
}
