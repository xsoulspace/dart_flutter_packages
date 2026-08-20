// ignore_for_file: lines_longer_than_80_chars

/// Phase 1 — tests for cinematic projection.
///
/// Verifies the projection system is a real film cut: relevance-ranked,
/// budget-limited, green-screen-explicit, and that the model only ever sees
/// the projected slice (never raw history). Projection ray-traces the graph
/// via [FacetIndex] and the actor's [ActorThreads].
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'agent_harness_test.dart' show MockGenerationHandler, buildTestWorld;

/// Spawn a complete text beat in [thread] and index it under [keywords].
Entity _addBeat(
  World world,
  Entity thread,
  Entity speaker,
  String text,
  List<String> keywords,
) {
  final beat = startBeat(world, thread, speaker, BeatModalityEnum.text);
  appendToBeat(world, beat, text);
  completeBeat(world, beat);
  indexBeat(world, beat, keywords);
  world.flush();
  return beat;
}

/// Run the projection schedule for the given world.
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
      world.flush();
      // Spawn an actor with an OpenDecision about the parser.
      final speaker = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorSystemPrompt(text: 'You are a helpful assistant.'),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Fix the parser bug'),
        ActorThreads(threads: []),
      ]);
      world.flush();
      final thread = spawnThread(world, speaker, scene);
      world.upsertComponent(speaker, ActorThreads(threads: [thread]));
      world.flush();

      // One beat relevant to "parser", one irrelevant.
      final relevant = _addBeat(
        world,
        thread,
        speaker,
        'The parser fails on nested brackets.',
        const ['parser', 'brackets'],
      );
      _addBeat(world, thread, speaker, 'The weather today is sunny.', const [
        'weather',
        'sunny',
      ]);

      _project(world);

      final situation = world.getEntity(speaker).$1.get<Situation>()!;
      expect(situation.projectedBeats, isNotEmpty);
      // The relevant beat should be ranked first.
      expect(situation.projectedBeats.first, relevant);
    });

    test('enforces the token budget and flags truncation', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 20));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
      ]);
      world.flush();
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();
      world.upsertComponent(actor, const OpenDecision(prompt: 'Q'));
      world.flush();

      // Add a very long beat that cannot fit in a 20-token budget.
      _addBeat(world, thread, actor, 'x' * 500, const ['x']);
      world.flush();

      _project(world);

      final situation = world.getEntity(actor).$1.get<Situation>()!;
      expect(situation.tokenBudget, 20);
      // The long beat was cut — nothing fits in the budget.
      expect(situation.projectedBeats, isEmpty);
      expect(situation.truncated, isTrue);
      expect(situation.tokensUsed, lessThanOrEqualTo(20));
    });

    test('adds green-screen absences when context is cut', () async {
      final world = await buildTestWorld();
      world.upsertResource(ProjectionBudget(tokens: 10));
      world.flush();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Q'),
      ]);
      world.flush();
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      _addBeat(world, thread, actor, 'y' * 300, const <String>[]);
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
        final actor = world.spawnComponents([
          Actor(agentId: AgentId.create()),
          ActorModel(modelId: ModelId.create()),
          PresentInScene(sceneEntity: scene),
          const OpenDecision(prompt: 'Q'),
        ]);
        world.flush();
        final thread = spawnThread(world, actor, scene);
        world.upsertComponent(actor, ActorThreads(threads: [thread]));
        world.flush();

        // Add one short beat that fits and one long beat that must be cut.
        _addBeat(world, thread, actor, 'short', const ['shortfolio']);
        _addBeat(world, thread, actor, 'z' * 400, const ['zzzz']);
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
