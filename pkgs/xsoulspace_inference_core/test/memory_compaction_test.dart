// ignore_for_file: lines_longer_than_80_chars

/// Phase 2 — tests for bounded memory via mechanical delegation.
///
/// Verifies that the harness (not the model) owns history: old raw fragments
/// are compacted into summaries so the projected context stays bounded.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'agent_harness_test.dart' show buildTestWorld;

/// Fill an actor's memory with [count] raw text fragments.
void _fillMemory(World world, Entity actor, int count) {
  final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
  for (var i = 0; i < count; i++) {
    final beat = world.spawnComponents([
      TextContent('fragment $i content'),
      BeatStatus(BeatStatusEnum.complete),
    ]);
    memories.fragments.add(
      ContextFragment(type: ContextFragmentType.modelResponse, beat: beat),
    );
  }
  world.flush();
}

void main() {
  group('compactMemorySystem', () {
    test('does nothing below the threshold', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();

      _fillMemory(world, actor, 5);

      world.runSchedule('Narrative');
      world.flush();

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      expect(memories.fragments.length, 5);
      expect(
        memories.fragments.where(
          (f) => f.type == ContextFragmentType.memorySummary,
        ),
        isEmpty,
      );
    });

    test('compacts old fragments into a summary above the threshold', () async {
      final world = await buildTestWorld();
      // Lower the threshold so the test is fast.
      world.upsertResource(
        MemoryCompactionPolicy(maxRawFragments: 6, summaryEvery: 4),
      );
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();

      _fillMemory(world, actor, 10);

      world.runSchedule('Narrative');
      world.flush();

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      // 10 raw - 4 compacted = 6 raw + 1 summary = 7 fragments.
      expect(memories.fragments.length, 7);

      final summaryFragments = memories.fragments
          .where((f) => f.type == ContextFragmentType.memorySummary)
          .toList();
      expect(summaryFragments.length, 1);

      // The summary beat carries MemorySummary + SummaryOwner.
      final summaryBeat = world.getEntity(summaryFragments.first.beat).$1;
      expect(summaryBeat.has<MemorySummary>(), isTrue);
      expect(summaryBeat.get<SummaryOwner>()?.actor, actor);
    });

    test('keeps the projected context bounded after compaction', () async {
      final world = await buildTestWorld();
      world.upsertResource(
        MemoryCompactionPolicy(maxRawFragments: 6, summaryEvery: 4),
      );
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Continue'),
      ]);
      world.flush();

      _fillMemory(world, actor, 10);

      // Compact, then project.
      world.runSchedule('Narrative');
      world.flush();
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      // The projected context is bounded — summaries, not 10 raw fragments.
      expect(situation.contextFragments.length, lessThanOrEqualTo(8));
      // At least one projected fragment is a summary.
      expect(
        situation.contextFragments.where(
          (f) => f.type == ContextFragmentType.memorySummary,
        ),
        isNotEmpty,
      );
    });

    test('derives memory cache from the thread graph (graph-native)', () async {
      final world = await buildTestWorld();
      world.upsertResource(
        MemoryCompactionPolicy(maxRawFragments: 6, summaryEvery: 4),
      );
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();

      // Link the actor to a thread, then add beats INTO the thread.
      final thread = spawnThread(world, actor, scene);
      linkActorToThreads(world, actor, [thread]);
      world.flush();

      for (var i = 0; i < 10; i++) {
        final beat = startBeat(world, thread, actor, BeatModalityEnum.text);
        appendToBeat(world, beat, 'fragment $i content');
        completeBeat(world, beat);
      }
      world.flush();

      // Compact — graph transformation over the thread.
      world.runSchedule('Narrative');
      world.flush();

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      // The cache now reflects the thread graph (beats + summary), not raw
      // fragment appends. Archived beats dropped from projection view.
      final summaries = memories.fragments
          .where((f) => f.type == ContextFragmentType.memorySummary)
          .toList();
      expect(summaries, isNotEmpty);
      // The summary node stays in the thread.
      final summaryBeat = world.getEntity(summaries.first.beat).$1;
      expect(summaryBeat.get<BelongsToThread>()?.thread, thread);
      expect(summaryBeat.has<MemorySummary>(), isTrue);
    });
  });
}
