// ignore_for_file: lines_longer_than_80_chars

/// projectSituationSystem — building the cinematic [Situation] per actor.
///
/// Covers props in frame, co-present actors, and the local question. Deep
/// relevance / budget / ray-trace behavior lives in `projection_test.dart`;
/// this file only locks the situation assembly that does not need an index.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('projectSituationSystem', () {
    test('builds a Situation carrying the local question', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'What is the answer?',
      );
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      final (entity, valid) = world.getEntity(actor);
      expect(valid, isTrue);
      final situation = entity.get<Situation>();
      expect(situation, isNotNull);
      expect(situation!.prompt, 'What is the answer?');
      expect(situation.inFramePropIds, isEmpty);
      expect(situation.coPresentActorIds, isEmpty);
    });

    test('includes co-present actors in the Situation', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'Q1');
      spawnActor(world, scene, openDecisionPrompt: 'Q2');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      // At least one actor sees the other as co-present.
      final actors = world.query2<Actor, Agency>().toList();
      final anyCoPresent = actors.any(
        (e) => (e.$1.get<Situation>()?.coPresentActorIds.length ?? 0) > 0,
      );
      expect(anyCoPresent, isTrue);
    });

    test('includes props in frame in the Situation', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      world.spawnComponents([
        const Prop(name: 'test_file'),
        PresentProp(sceneEntity: scene),
      ]);
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      final situation = world.getEntity(actor).$1.get<Situation>();
      expect(situation?.inFramePropIds, contains('test_file'));
    });
  });
}
