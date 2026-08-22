// ignore_for_file: lines_longer_than_80_chars

/// Multi-thread projection: visibility, status filtering, private beats,
/// and targeted decisions ([OpenDecision.threadId]).

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  test('projection ray-traces all actor threads, not just the first', () async {
    final handler = MockGenerationHandler(responseText: 'ok');
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();

    // Two threads, each with a distinct indexed beat.
    final threadA = spawnThread(world, actor, scene);
    final threadB = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [threadA, threadB]));
    addIndexedBeat(world, threadA, actor, 'quantum flux capacitor', [
      'quantum',
      'flux',
    ]);
    addIndexedBeat(world, threadB, actor, 'steam boiler pressure', [
      'steam',
      'boiler',
    ]);
    // A decision is required so AgencyGrant grants agency and projection runs.
    world.upsertComponent(actor, OpenDecision(prompt: 'quantum and boiler'));
    world.flush();

    projectFor(world);

    final situation = world.getEntity(actor).$1.get<Situation>();
    expect(situation, isNotNull);
    final texts = situation!.projectedBeats.map(
      (b) => world.getEntity(b).$1.get<TextContent>()?.text ?? '',
    );
    expect(texts.any((t) => t.contains('quantum')), isTrue);
    expect(texts.any((t) => t.contains('boiler')), isTrue);
  });

  test('pruned threads are excluded from projection', () async {
    final handler = MockGenerationHandler(responseText: 'ok');
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();

    final activeThread = spawnThread(world, actor, scene);
    final prunedThread = spawnThread(world, actor, scene);
    world.upsertComponent(
      actor,
      ActorThreads(threads: [activeThread, prunedThread]),
    );
    addIndexedBeat(world, activeThread, actor, 'visible signal', ['signal']);
    addIndexedBeat(world, prunedThread, actor, 'buried secret', ['secret']);
    world.flush();

    // Prune the second thread and deindex its beats (as pruneThreadsSystem does).
    world
        .getEntity(prunedThread)
        .$1
        .insert(ThreadStatus(ThreadStatusEnum.pruned));
    deindexBeat(world, beatsWithText(world, 'buried secret').first);
    world.upsertComponent(actor, OpenDecision(prompt: 'signal or secret?'));
    world.flush();

    projectFor(world);

    final situation = world.getEntity(actor).$1.get<Situation>();
    final texts = situation!.projectedBeats.map(
      (b) => world.getEntity(b).$1.get<TextContent>()?.text ?? '',
    );
    expect(texts.any((t) => t.contains('signal')), isTrue);
    expect(texts.any((t) => t.contains('secret')), isFalse);
  });

  test('private beats of other actors never enter another actor cut', () async {
    final handler = MockGenerationHandler(responseText: 'ok');
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final alice = spawnActor(world, scene);
    final bob = spawnActor(world, scene);
    world.flush();

    final sharedThread = spawnThread(world, alice, scene);
    world
      ..upsertComponent(alice, ActorThreads(threads: [sharedThread]))
      ..upsertComponent(bob, ActorThreads(threads: [sharedThread]));

    // Alice writes a beat private to herself in the shared thread.
    final beat = addIndexedBeat(world, sharedThread, alice, 'hidden diary', [
      'diary',
    ]);
    world.getEntity(beat).$1.insert(PrivateToActor(alice));

    // Bob's decision mentions "diary" — the keyword hits, but privacy blocks it.
    world.upsertComponent(bob, OpenDecision(prompt: 'what about diary?'));
    world.flush();
    projectFor(world);

    final situation = world.getEntity(bob).$1.get<Situation>();
    expect(situation, isNotNull);
    final texts = situation!.projectedBeats.map(
      (b) => world.getEntity(b).$1.get<TextContent>()?.text ?? '',
    );
    expect(texts.any((t) => t.contains('diary')), isFalse);
  });

  test('OpenDecision.threadId targets beat attachment', () async {
    final handler = MockGenerationHandler(responseText: 'targeted answer');
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();

    final defaultThread = spawnThread(world, actor, scene);
    final targetThread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [defaultThread]));

    // Decision targets the second thread.
    world.upsertComponent(
      actor,
      OpenDecision(prompt: 'go', threadId: targetThread),
    );
    world.flush();

    // Full cinematic cycle so agency is granted and projection runs.
    world.runSchedule(Schedules.agencyGrant);
    world.flush();
    world.runSchedule(Schedules.project);
    world.flush();
    await world.runScheduleAsync(Schedules.actorAct);
    world.flush();
    world.runSchedule(Schedules.processResponses);
    world.flush();

    // The response beat landed in the targeted thread, not the default one.
    final responseBeats = beatsWithText(world, 'targeted answer');
    expect(responseBeats, hasLength(1));
    final belongs = world
        .getEntity(responseBeats.first)
        .$1
        .get<BelongsToThread>();
    expect(belongs?.thread, targetThread);
  });

  test('stopwords do not dominate keyword matching', () async {
    final handler = MockGenerationHandler(responseText: 'ok');
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();

    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    addIndexedBeat(world, thread, actor, 'parser fails on nested brackets', [
      'parser',
      'brackets',
    ]);
    world.flush();

    // A prompt of pure stopwords + one real term still ray-traces the term.
    world.upsertComponent(
      actor,
      OpenDecision(prompt: 'the parser and this with that'),
    );
    world.flush();
    projectFor(world);

    final situation = world.getEntity(actor).$1.get<Situation>();
    final texts = situation!.projectedBeats.map(
      (b) => world.getEntity(b).$1.get<TextContent>()?.text ?? '',
    );
    expect(texts.any((t) => t.contains('parser')), isTrue);
  });
}
