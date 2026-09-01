// ignore_for_file: lines_longer_than_80_chars

/// Cinematic projection tests — the projection system is a film cut.
///
/// Verifies projection is relevance-ranked, budget-limited, green-screen-
/// explicit, and that the model only ever sees the projected slice (never
/// raw history). Projection ray-traces the graph via [FacetIndex] and the
/// actor's [ActorThreads].
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('cinematic projection', () {
    test('ranks relevant beats above irrelevant ones', () async {
      final world = await buildTestWorld();
      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      world.flush();
      final speaker = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        const ActorSystemPrompt(text: 'You are a helpful assistant.'),
        PresentInScene(sceneEntity: scene),
        const OpenDecision(prompt: 'Fix the parser bug'),
        ActorThreads(threads: []),
      ]);
      world.flush();
      final thread = spawnThread(world, speaker, scene);
      world.upsertComponent(speaker, ActorThreads(threads: [thread]));
      world.flush();

      final relevant = addIndexedBeat(
        world,
        thread,
        speaker,
        'The parser fails on nested brackets.',
        const ['parser', 'brackets'],
      );
      addIndexedBeat(
        world,
        thread,
        speaker,
        'The weather today is sunny.',
        const ['weather', 'sunny'],
      );

      projectFor(world);

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
      addIndexedBeat(world, thread, actor, 'x' * 500, const ['x']);
      world.flush();

      projectFor(world);

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

      addIndexedBeat(world, thread, actor, 'y' * 300, const <String>[]);
      world.flush();

      projectFor(world);

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

        // One short beat that fits and one long beat that must be cut.
        addIndexedBeat(world, thread, actor, 'short', const ['shortfolio']);
        addIndexedBeat(world, thread, actor, 'z' * 400, const ['zzzz']);
        world.flush();

        projectFor(world);
        await world.runScheduleAsync(Schedules.actorAct);
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

  group('plan frontier projection', () {
    test('traverses explicit dependencies and omits off-screen steps', () {
      final world = buildMinimalWorld();
      final goal = world.spawnComponents([Goal(text: 'ship')]);
      final first = world.spawnComponents([
        GoalLink(goal),
        Step(claim: 'first'),
      ]);
      final second = world.spawnComponents([
        GoalLink(goal),
        DependsOnStep([first]),
        Step(claim: 'second'),
      ]);
      final third = world.spawnComponents([
        GoalLink(goal),
        DependsOnStep([second]),
        Step(claim: 'third'),
      ]);
      final blocked = world.spawnComponents([
        GoalLink(goal),
        Step(claim: 'blocked', status: StepLifecycle.blocked),
      ]);
      world.flush();

      final projection = projectPlanFrontier(
        world,
        null,
        budget: 100,
        estimator: defaultTokenEstimator,
      );

      expect(projection.steps, [first, second, third]);
      expect(projection.tokensUsed, greaterThan(0));
      expect(projection.truncated, isFalse);
      expect(blocked, isNot(inProjection(projection)));
    });

    test('does not select a step before its dependency is verified', () {
      final world = buildMinimalWorld();
      final first = world.spawnComponents([
        const GoalLink(null),
        Step(claim: 'first', status: StepLifecycle.verified),
      ]);
      final second = world.spawnComponents([
        DependsOnStep([first]),
        Step(claim: 'second'),
      ]);
      world.flush();

      final projection = projectPlanFrontier(
        world,
        second,
        budget: 10,
        estimator: defaultTokenEstimator,
      );

      expect(projection.steps, [second]);
    });
  });
}

Matcher inProjection(PlanProjection projection) =>
    predicate<Entity>((e) => projection.steps.contains(e), 'in projection');

World buildMinimalWorld() {
  final world = World()..addPlugin(AgentPlugin());
  world.flush();
  return world;
}
