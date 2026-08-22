// ignore_for_file: lines_longer_than_80_chars

/// HarnessLoop — idle/sleep semantics and the multi-actor e2e.
///
/// `canSleep` must be true only when no work remains (no open decisions, no
/// agency, no awaiting responses, no in-flight tasks). The loop iterates the
/// schedules; this file drives them by hand to assert both sleep predicates
/// and a concurrent multi-actor cycle end to end.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('HarnessLoop canSleep', () {
    test('returns true when nothing is pending', () async {
      final world = await buildTestWorld();
      final loop = HarnessLoop(world: world);
      expect(loop.canSleep(), isTrue);
    });

    test('returns false when an OpenDecision exists', () async {
      final world = await buildTestWorld();
      final loop = HarnessLoop(world: world);
      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'Decide something.');
      world.flush();
      expect(loop.canSleep(), isFalse);
    });

    test('returns false while Agency is held', () async {
      final world = await buildTestWorld();
      final loop = HarnessLoop(world: world);
      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      expect(loop.canSleep(), isFalse);
    });

    test('returns false while a response is awaited', () async {
      final handler = MockGenerationHandler(responseText: 'hello');
      final world = await buildTestWorld(handler: handler);
      final loop = HarnessLoop(world: world);
      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      expect(loop.canSleep(), isFalse);

      world.runSchedule(Schedules.processResponses);
      world.flush();
      expect(loop.canSleep(), isTrue);
    });
  });

  group('multi-actor full loop (e2e)', () {
    test(
      'processes three concurrent actors and writes indexed beats',
      () async {
        final handler = MockGenerationHandler(responseText: 'response');
        final world = await buildTestWorld(handler: handler);
        final scene = spawnScene(world);

        final actors = List.generate(
          3,
          (i) => spawnActor(
            world,
            scene,
            openDecisionPrompt: 'Actor $i: respond with a number.',
            systemPrompt: 'You are actor $i.',
          ),
        );
        world.flush();

        // Grant + project all.
        world.runSchedule(Schedules.agencyGrant);
        world.flush();
        world.runSchedule(Schedules.project);
        world.flush();
        for (final actor in actors) {
          expect(world.getEntity(actor).$1.has<Situation>(), isTrue);
        }

        // All act concurrently, then all responses processed.
        await world.runScheduleAsync(Schedules.actorAct);
        world.flush();
        for (final actor in actors) {
          expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
        }
        world.runSchedule(Schedules.processResponses);
        world.flush();

        final index = world.getResource<FacetIndex>();
        for (final actor in actors) {
          expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
          expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
        }
        expect(index.beatsFor(const ['response']), isNotEmpty);
      },
    );

    test('re-grants agency when a new OpenDecision arrives', () async {
      final handler = MockGenerationHandler(responseText: 'done');
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'First.');
      world.flush();

      // First cycle.
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      world.runSchedule(Schedules.processResponses);
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);

      // Second cycle.
      world.upsertComponent(actor, const OpenDecision(prompt: 'Second.'));
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      world.runSchedule(Schedules.project);
      world.flush();
      await world.runScheduleAsync(Schedules.actorAct);
      world.flush();
      world.runSchedule(Schedules.processResponses);
      world.flush();

      final index = world.getResource<FacetIndex>();
      expect(index.beatsFor(const ['done']).toList(), hasLength(2));
    });
  });
}
