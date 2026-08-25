// ignore_for_file: lines_longer_than_80_chars

/// End-to-end coverage for PersistentId-based persistence (A8):
/// identity stability across save/load boundaries, privacy-respecting cut
/// parity, and a restored world that keeps living through further turns.
import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/agent.dart';

import 'support/agent_harness_support.dart';

void main() {
  late Directory tempDir;
  late SnapshotStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness-e2e-test');
    store = SnapshotStore();
    await store.open(tempDir.path);
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('persistent ids are stable across a full store round trip', () async {
    final world = _twoActorWorld();

    await store.save(world, name: 'first');
    final reloaded = await store.load('first');
    await store.save(reloaded, name: 'second');

    final first = _readWorldPayload(tempDir, 'first');
    final second = _readWorldPayload(tempDir, 'second');
    // Runtime Entity handles were regenerated between the two saves, yet
    // the payloads are identical: identity flows through PersistentId only.
    expect(second, equals(first));
    expect((second['payload'] as Map)['entities'] as List, isNotEmpty);
  });

  test('cuts survive restore byte-for-byte, privacy included', () async {
    final world = _twoActorWorld();
    world.runSchedule(Schedules.agencyGrant);
    world.flush();
    world.runSchedule(Schedules.project);
    world.flush();

    final before = _cutsByAgent(world);
    expect(before['ada'], isNotEmpty);
    // The private beat reaches maya's cut only.
    expect(
      before['maya']!.any(
        (line) => line.contains('quietly patch the flaky test'),
      ),
      isTrue,
    );
    expect(
      before['ada']!.any((line) => line.contains('quietly patch')),
      isFalse,
    );

    await store.save(world, name: 'cuts');
    final restored = await store.load('cuts');
    restored.runSchedule(Schedules.agencyGrant);
    restored.flush();
    restored.runSchedule(Schedules.project);
    restored.flush();

    // Byte-match: no loss, no leakage, privacy preserved, and even the
    // recency tie-break order inside each cut reproduces exactly.
    expect(_cutsByAgent(restored), equals(before));

    final originalHits = world.getResource<FacetIndex>().beatsFor([
      'flaky',
    ]).length;
    final restoredHits = restored.getResource<FacetIndex>().beatsFor([
      'flaky',
    ]).length;
    expect(restoredHits, originalHits);
    expect(restoredHits, greaterThan(0));
  });

  test(
    'restored world keeps living: new turns append beats and persist',
    () async {
      final world = _twoActorWorld();
      await store.save(world, name: 'session');
      final restored = await store.load('session');

      restored.getResource<GenerationHandlerResource>().registerDefault(
        MockGenerationHandler(responseText: 'continuing the plan'),
      );
      // Settle the decisions the world was saved with, then open exactly one
      // new one so the turn count is deterministic.
      for (final (entity, _, _)
          in restored.query2<Actor, OpenDecision>().toList()) {
        entity.remove<OpenDecision>();
      }
      final restoredActor = restored
          .query<Actor>()
          .map((r) => r.$1)
          .firstWhere((f) => f.get<Actor>()!.agentId.value == 'ada');
      restoredActor.insert(const OpenDecision(prompt: 'continue'));
      restored.flush();

      await HarnessLoop(world: restored).runUntilIdle();
      expectIdle(restored);
      final newBeats = beatsWithText(restored, 'continuing the plan');
      expect(newBeats, hasLength(1));

      // Idle worlds carry no Situations (derived at agency time, excluded
      // from snapshots by design) — assert narrative content parity instead.
      final textsAfterTurn = _beatTexts(restored);
      await store.save(restored, name: 'after-turn');
      final reloaded = await store.load('after-turn');
      expect(_beatTexts(reloaded), equals(textsAfterTurn));
      expect(beatsWithText(reloaded, 'continuing the plan'), hasLength(1));
    },
  );
}

List<String> _beatTexts(World world) {
  final texts = <String>[];
  for (final (facade, text, _)
      in world.query2<TextContent, BelongsToThread>()) {
    texts.add('${facade.get<BeatSequence>()?.value ?? -1}:${text.text}');
  }
  return texts..sort();
}

Map<String, Object?> _readWorldPayload(Directory dir, String name) =>
    (jsonDecode(
              File(
                '${dir.path}/harness-sessions/$name.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)['world']
        as Map<String, Object?>;

/// Per-actor projection cuts keyed by agent id, deterministically ordered.
Map<String, List<String>> _cutsByAgent(World world) {
  final cuts = <String, List<String>>{};
  for (final (entity, _, situation) in world.query2<Actor, Situation>()) {
    final id = entity.get<Actor>()!.agentId.value;
    cuts[id] = [
      'prompt: ${situation.prompt}',
      for (final beat in situation.projectedBeats)
        world.getEntity(beat).$1.get<TextContent>()?.text ?? '',
    ];
  }
  return cuts;
}

/// Two actors sharing one thread: public coordination beat, a beat private
/// to maya, and a goal graph with a verified step and tool-result evidence.
World _twoActorWorld() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final ada = world.spawnComponents([
    Actor(agentId: const AgentId('ada')),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'You are ada.'),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'Plan the release'),
  ]);
  final maya = world.spawnComponents([
    Actor(agentId: const AgentId('maya')),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'You are maya.'),
    PresentInScene(sceneEntity: scene),
    const OpenDecision(prompt: 'Watch the release'),
  ]);
  world.flush();

  final goal = world.spawnComponents([Goal(text: 'ship release')]);
  final thread = world.spawnComponents([
    const Thread(),
    ThreadScore(0.9),
    const ThreadId('thread-release'),
    ThreadStatus(ThreadStatusEnum.active),
    ParentScene(scene),
    OriginActor(ada),
    GoalLink(goal),
  ]);
  world.flush();

  final step = world.spawnComponents([
    Step(
      claim: 'write regression tests',
      verificationKind: StepVerificationKind.mechanical,
      status: StepLifecycle.verified,
      confidence: 0.9,
    ),
    GoalLink(goal),
  ]);
  world.flush();

  void beat(
    String text, {
    Entity? speaker,
    Entity? addressedTo,
    Entity? privateTo,
    bool evidence = false,
  }) {
    final components = <Component>[
      TextContent(text),
      BeatStatus(BeatStatusEnum.complete),
      BeatModality(
        evidence ? BeatModalityEnum.observation : BeatModalityEnum.text,
      ),
      BelongsToThread(thread),
      BeatSequence(world.query<BeatSequence>().toList().length),
    ];
    if (speaker != null) components.add(Speaker(speaker));
    if (addressedTo != null) components.add(AddressedTo(addressedTo));
    if (privateTo != null) components.add(PrivateToActor(privateTo));
    if (evidence) {
      components
        ..add(ToolResultContent(name: 'run_tests', output: '{"passed": true}'))
        ..add(GoalLink(goal))
        ..add(DependsOnStep([step]));
    }
    final e = world.spawnComponents(components);
    indexBeat(world, e, keywordsOf(text), thread: thread);
  }

  beat('release plan drafted', speaker: ada);
  beat('quietly patch the flaky test', speaker: maya, privateTo: maya);
  beat(
    '<result|run_tests|{"passed": true}>',
    speaker: maya,
    addressedTo: ada,
    evidence: true,
  );

  world.upsertComponent(ada, ActorThreads(threads: [thread]));
  world.upsertComponent(maya, ActorThreads(threads: [thread]));
  world.flush();
  return world;
}
