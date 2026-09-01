import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart';

void main() {
  test('restores graph and reproduces projection byte-for-byte', () {
    final original = World()..addPlugin(AgentPlugin());
    original.upsertResource(ModelRouterResource(ModelRouter()));
    final scene = original.spawnComponents([const Scene(), SceneFrame()]);
    original.flush();
    final actor = original.spawnComponents([
      Actor(agentId: AgentId.create()),
      ActorModel(modelId: ModelId.create()),
      const ActorSystemPrompt(text: 'You are a planner.'),
      PresentInScene(sceneEntity: scene),
      Goal(text: 'ship', successCriteria: ['tests-pass']),
      const OpenDecision(prompt: 'What is next?'),
    ]);
    original.flush();
    final goal = original.query<Goal>().first.$1.entity;
    final thread = original.spawnComponents([
      const Thread(),
      ThreadScore(0.8),
      const ThreadId('thread-1'),
      ThreadStatus(ThreadStatusEnum.active),
      ParentScene(scene),
      OriginActor(actor),
      GoalLink(goal),
    ]);
    original.flush();
    final step = original.spawnComponents([
      Step(
        claim: 'restore works',
        verificationKind: StepVerificationKind.mechanical,
        confidence: 0.5,
      ),
      const DependsOnStep(),
    ]);
    original.flush();
    final beat = startBeat(original, thread, actor, BeatModalityEnum.text);
    appendToBeat(original, beat, 'restore works');
    completeBeat(original, beat);
    indexBeat(original, beat, keywordsOf('restore works'), thread: thread);
    final identity = original.spawnComponents([
      TextContent('You are a planner.\nGoal: ship'),
      BeatStatus(BeatStatusEnum.complete),
      BeatModality(BeatModalityEnum.observation),
      const IdentityBeat(),
      BelongsToThread(thread),
    ]);
    original.flush();
    indexBeat(
      original,
      identity,
      keywordsOf('planner goal ship'),
      thread: thread,
    );
    original.getEntity(actor).$1.insert(ActorThreads(threads: [thread]));
    original.getEntity(actor).$1.insert(const Agency());
    original.getEntity(step).$1.insert(GoalLink(goal));
    original.runSchedule(Schedules.agencyGrant);
    original.flush();
    original.runSchedule(Schedules.project);
    original.flush();

    final before = _projectionTexts(original);
    expect(before, isNotEmpty);
    expect(
      original.getResource<FacetIndex>().beatsFor(['restore']),
      isNotEmpty,
    );

    final json = jsonEncode(snapshotWorld(original));
    final restored = restoreWorld(jsonDecode(json) as Map<String, dynamic>);
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

    expect(_projectionTexts(restored), equals(before));
    final hits = restored.getResource<FacetIndex>().beatsFor(['restore']);
    expect(hits, hasLength(1));
    expect(
      restored.getEntity(hits.single).$1.get<TextContent>()?.text,
      'restore works',
    );
  });
}

List<String> _projectionTexts(World world) => [
  for (final (entity, _, situation) in world.query2<Actor, Situation>())
    for (final beat in situation.projectedBeats)
      '${entity.get<Actor>()?.agentId.value}:${world.getEntity(beat).$1.get<TextContent>()?.text ?? ''}',
];
