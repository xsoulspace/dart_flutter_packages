// ignore_for_file: lines_longer_than_80_chars

/// Agency lifecycle — granting, the in-flight fence, and re-granting.
///
/// Covers `grantAgencySystem` rules and the [AwaitingResponse] lifecycle
/// (added when acting, consumed when the response is processed, and
/// preventing double-grant while in flight). Multi-actor e2e and the loop
/// sleep conditions live in `harness_loop_test.dart`.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('grantAgencySystem', () {
    test('grants Agency to actors with OpenDecision', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'Decide something.',
      );
      world.flush();

      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
    });

    test('does not grant twice when Agency is already present', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Decide.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
    });

    test('does not grant Agency without an OpenDecision', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
    });
  });

  group('AwaitingResponse lifecycle', () {
    test('is added when the actor acts and consumed on response', () async {
      final handler = MockGenerationHandler(responseText: 'hello');
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);

      await world.runScheduleAsync('ActorAct');
      world.flush();
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);

      world.runSchedule('ProcessResponses');
      world.flush();
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
    });

    test('prevents re-granting Agency while a response is in flight', () async {
      final handler = MockGenerationHandler(responseText: 'hello');
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);

      // A second grant pass must not re-grant (still has Agency + awaiting).
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
    });
  });
}
