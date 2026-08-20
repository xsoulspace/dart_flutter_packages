// ignore_for_file: lines_longer_than_80_chars

/// Phase 1 — tests for cinematic projection.
///
/// Verifies the projection system is a real film cut: relevance-ranked,
/// budget-limited, green-screen-explicit, and that the model only ever sees
/// the projected slice (never raw history).
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'agent_harness_test.dart' show MockGenerationHandler, buildTestWorld;

/// Spawn a scene + actor with an [OpenDecision].
Entity _spawnActor(
  World world,
  Entity scene, {
  String openDecisionPrompt = 'Q',
}) {
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    ActorRuntimeMemories(),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: openDecisionPrompt),
  ]);
  world.flush();
  return actor;
}

/// Run the projection schedule for the given actor.
void _project(World world) {
  world.runSchedule('AgencyGrant');
  world.flush();
  world.runSchedule('Project');
  world.flush();
}

void main() {
  group('cinematic projection', () {
    test('ranks relevant beats above irrelevant ones', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = _spawnActor(
        world,
        scene,
        openDecisionPrompt: 'Fix the parser bug',
      );
      world.flush();

      // Add memory beats: one relevant to "parser", one irrelevant.
      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      final relevant = world.spawnComponents([
        TextContent('The parser fails on nested brackets.'),
        BeatStatus(BeatStatusEnum.complete),
      ]);
      final irrelevant = world.spawnComponents([
        TextContent('The weather today is sunny.'),
        BeatStatus(BeatStatusEnum.complete),
      ]);
      memories.fragments.addAll([
        ContextFragment(
          type: ContextFragmentType.modelResponse,
          beat: irrelevant,
        ),
        ContextFragment(
          type: ContextFragmentType.modelResponse,
          beat: relevant,
        ),
      ]);
      world.flush();

      _project(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.contextFragments, isNotEmpty);
      // The relevant beat should be ranked first.
      expect(situation.contextFragments.first.beat, relevant);
    });

    test('enforces the token budget and flags truncation', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 20));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = _spawnActor(world, scene);
      world.flush();

      // Add a very long beat that cannot fit in a 20-token budget.
      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      final longBeat = world.spawnComponents([
        TextContent('x' * 500),
        BeatStatus(BeatStatusEnum.complete),
      ]);
      memories.fragments.add(
        ContextFragment(
          type: ContextFragmentType.modelResponse,
          beat: longBeat,
        ),
      );
      world.flush();

      _project(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.tokenBudget, 20);
      // The long beat was cut — nothing fits in the budget.
      expect(situation.contextFragments, isEmpty);
      expect(situation.truncated, isTrue);
      expect(situation.tokensUsed, lessThanOrEqualTo(20));
    });

    test('adds green-screen absences when context is cut', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 10));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = _spawnActor(world, scene);
      world.flush();

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
      final longBeat = world.spawnComponents([
        TextContent('y' * 300),
        BeatStatus(BeatStatusEnum.complete),
      ]);
      memories.fragments.add(
        ContextFragment(
          type: ContextFragmentType.modelResponse,
          beat: longBeat,
        ),
      );
      world.flush();

      _project(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.explicitAbsences, isNotEmpty);
      expect(
        situation.explicitAbsences.any((a) => a.contains('off-screen')),
        isTrue,
      );
    });

    test(
      'actorActSystem sends only the projected context to the model',
      () async {
        final handler = MockGenerationHandler(responseText: 'ok');
        final world = await buildTestWorld(handler: handler);
        world.upsertResource(ProjectionBudget(tokens: 30));
        world.flush();

        final scene = world.spawnComponents([const Scene(), SceneFrame()]);
        final actor = _spawnActor(world, scene);
        world.flush();

        // Add one short beat that fits and one long beat that must be cut.
        final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>()!;
        final shortBeat = world.spawnComponents([
          TextContent('short'),
          BeatStatus(BeatStatusEnum.complete),
        ]);
        final longBeat = world.spawnComponents([
          TextContent('z' * 400),
          BeatStatus(BeatStatusEnum.complete),
        ]);
        memories.fragments.addAll([
          ContextFragment(
            type: ContextFragmentType.modelResponse,
            beat: shortBeat,
          ),
          ContextFragment(
            type: ContextFragmentType.modelResponse,
            beat: longBeat,
          ),
        ]);
        world.flush();

        _project(world);
        await world.runScheduleAsync('ActorAct');
        world.flush();

        final reader = world.events.reader<ActorGenerateRequest>();
        expect(reader.isNotEmpty, isTrue);
        final request = reader.readAt(0);
        // The projected context contains the short beat but NOT the long one.
        final contextText = request.contextFragments.join(' ');
        expect(contextText, contains('short'));
        expect(contextText, isNot(contains('z' * 400)));
      },
    );
  });
}
