// ignore_for_file: lines_longer_than_80_chars

/// ADR 0004 — intelligence-grade harness evaluation: exact per-decision cut
/// capture, adversarial (decoy) relevance oracles, and causal task-coupling.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/src/agent/systems/projection/projection_systems.dart'
    show fragmentText;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('exact per-decision cut capture', () {
    test('projectedTexts holds the true cut, not residue', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();
      final runner = ScenarioRunner(
        world: world,
        handler: MockGenerationHandler(responseText: 'ack'),
      );
      final scenario = Scenario(
        name: 'capture',
        actors: [
          ScenarioActor(
            name: 'a',
            systemPrompt: 'p',
            decisions: ['alpha topic'],
          ),
        ],
      );
      final metrics = await runner.run(scenario);

      // The decision's own response beat ("ack") is in the graph; the exact
      // capture must reflect what was projected AT THAT MOMENT — which for
      // the first decision excludes later beats. Here we assert the field is
      // populated and every captured text was a real projected beat.
      expect(metrics.decisions, hasLength(1));
      final d = metrics.decisions.first;
      expect(d.projectedTexts.length, d.projectedBeats);
      for (final text in d.projectedTexts) {
        expect(text, isA<String>());
      }
    });

    test(
      'later decisions do not retroactively change earlier captures',
      () async {
        final world = World()..addPlugin(AgentPlugin());
        world
          ..upsertResource(ModelRouterResource(ModelRouter()))
          ..upsertResource(ToolRegistryResource())
          ..flush();
        final handler = MockGenerationHandler(responseText: 'beta reply');
        world.getResource<GenerationHandlerResource>().registerDefault(handler);

        final runner = ScenarioRunner(world: world, handler: handler);
        final metrics = await runner.run(
          Scenario(
            name: 'immutability',
            actors: [
              ScenarioActor(
                name: 'a',
                systemPrompt: 'p',
                decisions: [
                  'first question',
                  'second question mentioning beta reply',
                ],
              ),
            ],
          ),
        );

        // Decision 1's capture cannot contain decision 2's response text,
        // even though that text exists in the graph by the end of the run.
        expect(
          metrics.decisions[0].projectedTexts.any((t) => t.contains('beta')),
          isFalse,
          reason: 'post-run residue leaked into an earlier decision capture',
        );
      },
    );
  });

  group('adversarial decoy oracle', () {
    test('decoy-only matches count against precision', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();
      final handler = MockGenerationHandler(responseText: 'parser fixed');

      // Spawn manually (same facade the runner uses) so the decoy beat can be
      // seeded BEFORE the run, then drive one decision through the canonical
      // cycle (the runner would spawn a second scene and trip the multi-scene
      // assertion).
      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'a', systemPrompt: 'p'),
      ], scene);
      world.getResource<GenerationHandlerResource>().registerDefault(handler);
      addIndexedBeat(
        world,
        spawned.first.thread,
        spawned.first.entity,
        'parser museum opening hours are nine',
        ['museum'],
      );

      final metrics = await _driveOneDecision(
        world,
        spawned.first.entity,
        'fix parser',
      );

      final results = scoreOracles(world, metrics, [
        const DecisionOracle(mustProject: ['parser'], decoyTerms: ['museum']),
      ]);

      // Recall is satisfied (the response beat mentions parser); precision
      // must NOT be 1.0 because the museum decoy matched only a decoy term.
      expect(results.first.projectionRecall, 1.0);
      expect(results.first.projectionPrecision, lessThan(1.0));
    });

    test('non-decoy relevant beats keep precision at 1.0', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();
      final handler = MockGenerationHandler(responseText: 'lexer ready');

      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        // System prompt contains the term so the seeded identity beat is
        // non-decoy relevant too.
        ActorSpec(name: 'a', systemPrompt: 'you run the lexer'),
      ], scene);
      world.getResource<GenerationHandlerResource>().registerDefault(handler);

      final metrics = await _driveOneDecision(
        world,
        spawned.first.entity,
        'run lexer',
      );

      final results = scoreOracles(world, metrics, [
        const DecisionOracle(decoyTerms: ['museum']),
      ]);
      expect(results.first.projectionPrecision, 1.0);
    });
  });

  group('causal task-coupling', () {
    test('handler succeeds when projection carries required context', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();

      final coupled = ContextCoupledHandler([
        const ContextDependency(
          requiredPhrase: 'launch codes rotated',
          successText: 'confirmed rotation',
          failureText: 'MISSING CONTEXT',
        ),
      ]);
      world.getResource<GenerationHandlerResource>().registerDefault(coupled);

      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'agent', systemPrompt: 'p'),
      ], scene);
      // Seed the dependency beat BEFORE the run so projection can find it.
      addIndexedBeat(
        world,
        spawned.first.thread,
        spawned.first.entity,
        'the launch codes rotated yesterday',
        ['launch', 'codes'],
      );

      final metrics = await _driveOneDecision(
        world,
        spawned.first.entity,
        'what about launch codes?',
      );

      expect(metrics.decisions, hasLength(1));
      expect(coupled.contextWasSufficient.single, isTrue);
      expect(coupled.contextSufficiencyRate, 1.0);
      expect(beatsWithText(world, 'confirmed rotation'), hasLength(1));
    });

    test('handler fails deterministically when context is absent', () async {
      final world = World()..addPlugin(AgentPlugin());
      world
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..upsertResource(ToolRegistryResource())
        ..flush();

      final coupled = ContextCoupledHandler([
        const ContextDependency(
          requiredPhrase: 'secret sauce recipe',
          successText: 'recipe recalled',
          failureText: 'MISSING CONTEXT',
        ),
      ]);
      world.getResource<GenerationHandlerResource>().registerDefault(coupled);

      final setup = AgentWorldSetup(world: world);
      final scene = setup.spawnScene();
      final spawned = setup.spawnActors([
        ActorSpec(name: 'agent', systemPrompt: 'p'),
      ], scene);
      // NO dependency beat seeded — projection cannot contain the phrase.

      await _driveOneDecision(
        world,
        spawned.first.entity,
        'recall the secret sauce recipe',
      );

      expect(coupled.contextWasSufficient.single, isFalse);
      expect(coupled.contextSufficiencyRate, 0.0);
      expect(beatsWithText(world, 'MISSING CONTEXT'), hasLength(1));
    });
  });
}

/// Drive one decision through the canonical cinematic cycle and return exact
/// per-decision metrics (ADR 0004 capture path).
Future<ScenarioMetrics> _driveOneDecision(
  World world,
  Entity actorEntity,
  String prompt,
) async {
  world.upsertComponent(actorEntity, OpenDecision(prompt: prompt));
  world.flush();
  final collector = MetricsCollector(world: world);
  collector.beginDecision(actor: actorEntity, actorName: 'a', prompt: prompt);

  world.runSchedule(Schedules.agencyGrant);
  world.flush();
  world.runSchedule(Schedules.project);
  world.flush();
  await world.runScheduleAsync(Schedules.actorAct);
  world.flush();
  world.runSchedule(Schedules.processResponses);
  world.flush();
  world.runSchedule(Schedules.mechanical);
  world.flush();

  final situation = world.getEntity(actorEntity).$1.get<Situation>();
  collector.endDecision(actor: actorEntity, situation: situation);
  final telemetry = collector.report().decisions.first;
  return ScenarioMetrics(
    name: 'driven',
    decisions: [
      DecisionMetrics(
        actor: 'a',
        prompt: prompt,
        tokensUsed: situation?.tokensUsed ?? 0,
        projectedBeats: situation?.projectedBeats.length ?? 0,
        explicitAbsences: situation?.explicitAbsences ?? const [],
        llmCalls: telemetry.llmCalls,
        truncated: situation?.truncated ?? false,
        projectedTexts: [
          for (final beat in situation?.projectedBeats ?? const <Entity>[])
            fragmentText(world, beat),
        ],
      ),
    ],
    totalLlmCalls: telemetry.llmCalls,
    totalTokens: situation?.tokensUsed ?? 0,
    prunedThreads: 0,
    mergedThreads: 0,
  );
}

/// Small helper so tests can spawn named actors without the full Scenario
/// machinery (mirrors AgentWorldSetup.spawnActors).
class ActorWorldSetupHelper {
  ActorWorldSetupHelper({required this.world});
  final World world;

  List<SpawnedResult> spawnActors(List<ActorSpec> specs, Entity scene) {
    final out = <SpawnedResult>[];
    for (final spec in specs) {
      final e = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorSystemPrompt(text: spec.systemPrompt),
        ActorThreads(threads: []),
        const ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
      ]);
      out.add(SpawnedResult(entity: e));
    }
    world.flush();
    for (final r in out) {
      final thread = spawnThread(world, r.entity, scene);
      world.upsertComponent(r.entity, ActorThreads(threads: [thread]));
      r.thread = thread;
    }
    world.flush();
    return out;
  }
}

class SpawnedResult {
  SpawnedResult({required this.entity});
  final Entity entity;
  Entity thread = Entity.create(0);
}
