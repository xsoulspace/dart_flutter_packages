// ignore_for_file: lines_longer_than_80_chars

/// Graph-native facet index tests.
///
/// Verifies the replacement for the old "memory + compaction" primitive:
/// beats are indexed by keyword into a [FacetIndex], projection ray-traces
/// the graph (keyword hits + the actor's thread links), and summaries are
/// deliberate [summarizeThread] transforms that stay in their thread.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('FacetIndex', () {
    test('indexes beats by keyword and returns them via beatsFor', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final speaker = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();
      final thread = spawnThread(world, speaker, scene);
      world.flush();

      final beat = addIndexedBeat(
        world,
        thread,
        speaker,
        'The parser fails on nested brackets.',
        const ['parser', 'brackets'],
      );

      final index = world.getResource<FacetIndex>();
      expect(index.beatsFor(const ['parser']), contains(beat));
      expect(index.beatsFor(const ['brackets']), contains(beat));
      // Irrelevant keyword misses.
      expect(index.beatsFor(const ['weather']), isNot(contains(beat)));
      // The beat's keywords are retained.
      expect(index.keywordsFor(beat), containsAll(['parser', 'brackets']));
    });

    test('beatsFor unions hits across multiple keywords', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final speaker = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();
      final thread = spawnThread(world, speaker, scene);
      world.flush();

      final beatA = addIndexedBeat(
        world,
        thread,
        speaker,
        'The lexer produces tokens.',
        const ['lexer', 'tokens'],
      );
      final beatB = addIndexedBeat(
        world,
        thread,
        speaker,
        'The parser checks brackets.',
        const ['parser', 'brackets'],
      );

      final index = world.getResource<FacetIndex>();
      final hits = index.beatsFor(const ['lexer', 'parser']).toList();
      expect(hits, containsAll([beatA, beatB]));
    });
  });

  group('ray-tracing projection', () {
    test(
      'projects a beat indexed under a prompt keyword, not an irrelevant one',
      () async {
        final world = await buildTestWorld();
        final scene = world.spawnComponents([const Scene(), SceneFrame()]);
        final actor = world.spawnComponents([
          Actor(agentId: AgentId.create()),
          ActorModel(modelId: ModelId.create()),
          PresentInScene(sceneEntity: scene),
          ActorThreads(threads: []),
        ]);
        world.flush();
        final thread = spawnThread(world, actor, scene);
        world.upsertComponent(actor, ActorThreads(threads: [thread]));
        final otherThread = spawnThread(world, actor, scene);
        world.flush();

        // The relevant beat lives in the actor's thread and matches the prompt
        // keyword. The irrelevant beat lives in an UNLINKED thread, so it is
        // neither keyword-relevant nor thread-reachable.
        final relevant = addIndexedBeat(
          world,
          thread,
          actor,
          'The parser is fixed now.',
          const ['parser'],
        );
        final irrelevant = addIndexedBeat(
          world,
          otherThread,
          actor,
          'The weather is rainy.',
          const ['weather'],
        );
        world.flush();

        world.upsertComponent(
          actor,
          const OpenDecision(prompt: 'fix the parser'),
        );
        world.flush();
        world.runSchedule(Schedules.agencyGrant);
        world.flush();
        world.runSchedule(Schedules.project);
        world.flush();

        final situation = world.getEntity(actor).$1.get<Situation>()!;
        expect(situation.projectedBeats, contains(relevant));
        expect(situation.projectedBeats, isNot(contains(irrelevant)));
      },
    );

    test('projects beats reachable through the actor thread', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
        ActorThreads(threads: []),
      ]);
      world.flush();
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      // A beat with no shared prompt keyword, but reachable from the thread.
      final reachable = addIndexedBeat(
        world,
        thread,
        actor,
        'Just a passing observation.',
        const ['observation', 'passing'],
      );
      world.flush();

      world.upsertComponent(actor, const OpenDecision(prompt: 'say anything'));
      world.flush();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.projectedBeats, contains(reachable));
    });
  });

  group('summarizeThread', () {
    test(
      'creates a MemorySummary beat indexed under source keywords and stays in thread',
      () async {
        final world = await buildTestWorld();
        final scene = world.spawnComponents([const Scene(), SceneFrame()]);
        final speaker = world.spawnComponents([
          Actor(agentId: AgentId.create()),
          ActorModel(modelId: ModelId.create()),
          PresentInScene(sceneEntity: scene),
        ]);
        world.flush();
        final thread = spawnThread(world, speaker, scene);
        world.flush();

        final source1 = addIndexedBeat(
          world,
          thread,
          speaker,
          'The lexer produces tokens.',
          const ['lexer', 'tokens'],
        );
        final source2 = addIndexedBeat(
          world,
          thread,
          speaker,
          'The parser checks nested brackets.',
          const ['parser', 'brackets'],
        );
        world.flush();

        final summary = summarizeThread(world, thread, [source1, source2]);
        world.flush();

        // A MemorySummary beat exists, stays in the thread, links its sources.
        final se = world.getEntity(summary).$1;
        expect(se.has<MemorySummary>(), isTrue);
        expect(se.get<BelongsToThread>()?.thread, thread);
        expect(
          se.get<SummarizesBeats>()?.sources,
          containsAll([source1, source2]),
        );

        // Indexed under the union of source keywords.
        final index = world.getResource<FacetIndex>();
        expect(index.beatsFor(const ['parser']), contains(summary));
        expect(index.beatsFor(const ['lexer']), contains(summary));
      },
    );
  });
}
