import 'dart:convert';
import 'dart:io';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart';

void main() {
  late Directory tempDir;
  late SnapshotStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness-sessions-test');
    store = SnapshotStore();
    await store.open(tempDir.path);
  });

  tearDown(() => tempDir.delete(recursive: true));

  test(
    'round-trips save -> list -> load through the real filesystem',
    () async {
      final (world, _) = _decisionWorld();
      final path = await store.save(world, name: 'alpha');

      expect(path, 'harness-sessions/alpha.json');
      expect(
        File('${tempDir.path}/harness-sessions/alpha.json').existsSync(),
        isTrue,
      );
      expect(await store.listSessions(), ['alpha']);

      final loaded = await store.load('alpha');
      expect(
        loaded.query<Actor>().first.$2.agentId,
        world.query<Actor>().first.$2.agentId,
      );
      expect(loaded.query<Goal>().first.$2.text, 'ship release');
      final steps = [
        for (final (_, step) in loaded.query<Step>())
          '${step.claim}:${step.status.name}',
      ]..sort();
      expect(steps, [
        'tag the release:open',
        'write regression tests:verified',
      ]);
      final dependency = loaded
          .query<DependsOnStep>()
          .map((record) => record.$2)
          .firstWhere((link) => link.dependencies.isNotEmpty);
      expect(
        loaded.getEntity(dependency.dependencies.single).$1.get<Step>()?.claim,
        'write regression tests',
      );
      expect(loaded.query<OpenDecision>().first.$2.prompt, 'Ship now or wait?');
    },
  );

  test('lists sessions sorted without extension', () async {
    final (world, _) = _decisionWorld();
    await store.save(world, name: 'zeta');
    await store.save(world, name: 'alpha');
    expect(await store.listSessions(), ['alpha', 'zeta']);
    await store.delete('zeta');
    expect(await store.listSessions(), ['alpha']);
  });

  test('missing session -> clear error', () async {
    await expectLater(
      store.load('ghost'),
      throwsA(isA<SnapshotNotFoundException>()),
    );
    expect(await store.listSessions(), isEmpty);
  });

  test('corrupt file -> clear error', () async {
    final (world, _) = _decisionWorld();
    final path = await store.save(world, name: 'broken');
    final file = File('${tempDir.path}/$path');

    await file.writeAsString('{not json');
    await expectLater(
      store.load('broken'),
      throwsA(isA<SnapshotFormatException>()),
    );

    await file.writeAsString(jsonEncode({'schema': 'someone-elses'}));
    await expectLater(
      store.load('broken'),
      throwsA(isA<SnapshotFormatException>()),
    );

    await file.writeAsString(
      jsonEncode({'schema': 'agent-harness-snapshot', 'version': 99}),
    );
    await expectLater(
      store.load('broken'),
      throwsA(isA<SnapshotFormatException>()),
    );

    await file.writeAsString(
      jsonEncode({'schema': 'agent-harness-snapshot', 'version': 1}),
    );
    await expectLater(
      store.load('broken'),
      throwsA(isA<SnapshotFormatException>()),
    );
  });

  test('meta survives round trip', () async {
    final (world, _) = _decisionWorld();
    await store.save(world, name: 'meta', meta: {'actor': 'maya', 'tick': 7});
    final raw = File(
      '${tempDir.path}/harness-sessions/meta.json',
    ).readAsStringSync();
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    expect(envelope['schema'], 'agent-harness-snapshot');
    expect(envelope['version'], 1);
    expect(envelope['savedAt'], isA<String>());
    expect(envelope['meta'], {'actor': 'maya', 'tick': 7});
  });

  test(
    'goals/steps golden: projections byte-equal across a store round trip',
    () async {
      final (world, _) = _decisionWorld();
      world.runSchedule(Schedules.agencyGrant);
      world.flush();
      world.runSchedule(Schedules.project);
      world.flush();

      final before = _projectionTexts(world);
      expect(before, isNotEmpty);
      expect(
        before.join('\n'),
        contains('<result|run_tests|{"passed": true}>'),
      );

      await store.save(world, name: 'golden');
      final restored = await store.load('golden');
      final restoredActor = restored.query<Actor>().first.$1.entity;
      final restoredThread = restored.query<ThreadId>().first.$1.entity;
      restored
          .getEntity(restoredActor)
          .$1
          .insert(ActorThreads(threads: [restoredThread]));
      restored.flush();
      restored.upsertResource(ModelRouterResource(ModelRouter()));
      restored.flush();
      restored.runSchedule(Schedules.project);
      restored.flush();

      expect(
        restored.query<Actor>().first.$2.agentId,
        world.query<Actor>().first.$2.agentId,
      );
      expect(
        restored.getResource<FacetIndex>().beatsFor(['release']),
        isNotEmpty,
      );
      expect(_projectionTexts(restored), equals(before));
    },
  );

  test('crash mid-decision: restore re-opens the decision and reproduces '
      'the cut', () {
    final (original, actor) = _decisionWorld();
    original.runSchedule(Schedules.agencyGrant);
    original.flush();
    // Crash point: the generation request was dispatched and is in flight.
    original
        .getEntity(actor)
        .$1
        .insert(const AwaitingResponse(taskId: TaskId('task-in-flight-42')));
    original.flush();
    original.runSchedule(Schedules.project);
    original.flush();

    final before = _projectionTexts(original);
    expect(before, isNotEmpty);
    final beforeSituation = original.getEntity(actor).$1.get<Situation>();
    expect(beforeSituation?.prompt, 'Ship now or wait?');

    final restored = restoreWorld(
      jsonDecode(jsonEncode(snapshotWorld(original))) as Map<String, dynamic>,
    );
    final restoredActor = restored.query<Actor>().first.$1.entity;
    final restoredThread = restored.query<ThreadId>().first.$1.entity;
    restored
        .getEntity(restoredActor)
        .$1
        .insert(ActorThreads(threads: [restoredThread]));
    restored.flush();
    restored.upsertResource(ModelRouterResource(ModelRouter()));
    restored.flush();

    final facade = restored.getEntity(restoredActor).$1;
    expect(facade.has<Agency>(), isTrue);
    expect(facade.get<AwaitingResponse>()?.taskId?.value, 'task-in-flight-42');
    expect(facade.get<OpenDecision>()?.prompt, 'Ship now or wait?');

    // The dangling taskId must not break any schedule.
    restored.runSchedule(Schedules.agencyGrant);
    restored.flush();
    restored.runSchedule(Schedules.project);
    restored.flush();

    expect(facade.has<OpenDecision>(), isTrue);
    final situation = facade.get<Situation>();
    expect(situation?.prompt, beforeSituation?.prompt);
    expect(_projectionTexts(restored), equals(before));
  });
}

/// Builds a world frozen mid-decision: an actor holding an [OpenDecision],
/// a goal graph (one verified step, one open dependent step), a completed
/// text beat, and a tool-result beat.
(World, Entity) _decisionWorld() {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    const ActorSystemPrompt(text: 'You are a planner.'),
    PresentInScene(sceneEntity: scene),
    Goal(text: 'ship release', successCriteria: ['tests-pass']),
    const OpenDecision(prompt: 'Ship now or wait?', priority: 3),
  ]);
  world.flush();
  final goal = world.query<Goal>().first.$1.entity;
  final thread = world.spawnComponents([
    const Thread(),
    ThreadScore(0.8),
    const ThreadId('thread-1'),
    ThreadStatus(ThreadStatusEnum.active),
    ParentScene(scene),
    OriginActor(actor),
    GoalLink(goal),
  ]);
  world.flush();
  final verifiedStep = world.spawnComponents([
    Step(
      claim: 'write regression tests',
      verificationKind: StepVerificationKind.mechanical,
      status: StepLifecycle.verified,
      confidence: 0.9,
    ),
    const DependsOnStep(),
    GoalLink(goal),
  ]);
  world.spawnComponents([
    Step(
      claim: 'tag the release',
      verificationKind: StepVerificationKind.mechanical,
      confidence: 0.5,
    ),
    DependsOnStep([verifiedStep]),
    GoalLink(goal),
  ]);
  world.flush();
  final beat = startBeat(world, thread, actor, BeatModalityEnum.text);
  appendToBeat(world, beat, 'release checklist updated');
  completeBeat(world, beat);
  indexBeat(
    world,
    beat,
    keywordsOf('release checklist updated'),
    thread: thread,
  );
  const result = ToolExecutionResult(
    name: 'run_tests',
    output: '{"passed": true}',
  );
  final toolText = toolResultText(result);
  final toolBeat = world.spawnComponents([
    ToolResultContent(name: result.name, output: result.output),
    Speaker(actor),
    BeatToolCall('run_tests', {'suite': 'all'}),
    TextContent(toolText),
    BeatStatus(BeatStatusEnum.complete),
    BeatModality(BeatModalityEnum.toolCall),
    BelongsToThread(thread),
  ]);
  world.flush();
  indexBeat(world, toolBeat, keywordsOf(toolText), thread: thread);
  world.getEntity(actor).$1.insert(ActorThreads(threads: [thread]));
  world.flush();
  return (world, actor);
}

List<String> _projectionTexts(World world) => [
  for (final (entity, _, situation) in world.query2<Actor, Situation>())
    for (final beat in situation.projectedBeats) _beatLine(world, entity, beat),
];

String _beatLine(World world, WorldEntity entity, Entity beat) =>
    '${entity.get<Actor>()?.agentId.value}:'
    '${world.getEntity(beat).$1.get<TextContent>()?.text ?? ''}';
