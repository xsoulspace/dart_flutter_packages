// ignore_for_file: lines_longer_than_80_chars

/// Phase 3 — agency policy + escalation.
///
/// Verifies that agency is granted by priority (not just "any decision"),
/// that concurrency is capped, and that escalation routes a decision to a
/// stronger model and folds the result back.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// Spawn an actor in a scene with an [OpenDecision] carrying priority/escalation.
Entity _spawnActor(
  World world,
  Entity scene, {
  String openDecisionPrompt = 'Q',
  int priority = 0,
  bool escalate = false,
}) {
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    PresentInScene(sceneEntity: scene),
    OpenDecision(
      prompt: openDecisionPrompt,
      priority: priority,
      escalate: escalate,
    ),
  ]);
  world.flush();
  return actor;
}

void main() {
  group('grantAgencySystem prioritization', () {
    test('grants agency to higher-priority decisions first', () async {
      final world = await buildTestWorld();
      world.upsertResource(AgencyPolicy(maxConcurrent: 1));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final low = _spawnActor(world, scene, priority: 1);
      final high = _spawnActor(world, scene, priority: 10);
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();

      // Only the high-priority actor gets agency (cap = 1).
      expect(world.getEntity(high).$1.has<Agency>(), isTrue);
      expect(world.getEntity(low).$1.has<Agency>(), isFalse);
    });

    test('caps concurrent agency grants', () async {
      final world = await buildTestWorld();
      world.upsertResource(AgencyPolicy(maxConcurrent: 2));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final a = _spawnActor(world, scene, priority: 3);
      final b = _spawnActor(world, scene, priority: 2);
      final c = _spawnActor(world, scene, priority: 1);
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();

      var granted = 0;
      for (final e in [a, b, c]) {
        if (world.getEntity(e).$1.has<Agency>()) granted++;
      }
      expect(granted, 2);
    });

    test('escalated decisions are granted before non-escalated', () async {
      final world = await buildTestWorld();
      world.upsertResource(AgencyPolicy(maxConcurrent: 1));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final normal = _spawnActor(world, scene, priority: 5);
      final escalated = _spawnActor(world, scene, priority: 5, escalate: true);
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();

      // Same priority, but escalated wins the tie.
      expect(world.getEntity(escalated).$1.has<Agency>(), isTrue);
      expect(world.getEntity(normal).$1.has<Agency>(), isFalse);
    });
  });

  group('escalation routing', () {
    test('routes an escalated request to a higher-tier model', () async {
      // Two models in the router; the actor binds to model-1 (tier 0).
      // model-2 is tier 1 — escalation must pick it, not an arbitrary model.
      final router = ModelRouter();
      router.models[const ModelId('model-1')] = const Model(
        id: ModelId('model-1'),
      );
      router.models[const ModelId('model-2')] = const Model(
        id: ModelId('model-2'),
        tier: 1,
      );

      final world = await buildTestWorld(router: router);
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      world.spawnComponents([
        Actor(agentId: AgentId.create()),
        const ActorModel(modelId: ModelId('model-1')),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Q', escalate: true),
        const EscalationRequest(reason: 'low confidence'),
      ]);
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();

      final reader = world.events.reader<ActorGenerateRequest>();
      expect(reader.isNotEmpty, isTrue);
      // The request was routed to the escalated (higher-tier) model.
      expect(reader.readAt(0).modelId, const ModelId('model-2'));
    });

    test(
      'escalation falls back to the current model when no higher tier exists',
      () async {
        // Both models are tier 0 — no strictly higher tier exists, so the
        // actor keeps its own model instead of jumping arbitrarily.
        final router = ModelRouter();
        router.models[const ModelId('model-1')] = const Model(
          id: ModelId('model-1'),
        );
        router.models[const ModelId('model-2')] = const Model(
          id: ModelId('model-2'),
        );

        final world = await buildTestWorld(router: router);
        world.flush();

        final scene = world.spawnComponents([const Scene(), SceneFrame()]);
        world.spawnComponents([
          Actor(agentId: AgentId.create()),
          const ActorModel(modelId: ModelId('model-1')),
          PresentInScene(sceneEntity: scene),
          const OpenDecision(prompt: 'Q', escalate: true),
          const EscalationRequest(reason: 'low confidence'),
        ]);
        world.flush();

        world.runSchedule(Schedules.agencyGrant);
        world.flush();
        world.runSchedule(Schedules.project);
        world.flush();
        await world.runScheduleAsync(Schedules.actorAct);
        world.flush();

        final reader = world.events.reader<ActorGenerateRequest>();
        expect(reader.isNotEmpty, isTrue);
        expect(reader.readAt(0).modelId, const ModelId('model-1'));
      },
    );

    test('clears EscalationRequest after the response is processed', () async {
      final handler = MockGenerationHandler(responseText: 'ok');
      final world = await buildTestWorld(handler: handler);
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Q', escalate: true),
        const EscalationRequest(reason: 'low confidence'),
      ]);
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      world.runSchedule(Schedules.processResponses);
      world.flush();

      expect(world.getEntity(actor).$1.has<EscalationRequest>(), isFalse);
    });
  });
}
