// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A mock handler that simulates an LLM without requiring Apple Foundation Models.
///
/// Returns a configurable [responseText] and optionally [toolCalls].
/// The handler processes requests synchronously when [processPending] is called,
/// mirroring how a real isolate handler would consume the event channel.
class MockActorGenerateHandler extends ActorGenerateHandler {
  MockActorGenerateHandler({
    required this.responseText,
    this.toolCalls = const [],
    this.responseOutput,
    this.delay = Duration.zero,
  });

  final String responseText;
  final List<ToolCall> toolCalls;
  final Map<String, dynamic>? responseOutput;
  final Duration delay;

  /// Process all pending requests in the world's event channel.
  ///
  /// This simulates what an external handler (Flutter isolate, CLI, etc.)
  /// would do: drain the request channel, call [handle] for each, and
  /// send responses back.
  Future<void> processPending(World world) async {
    final reader = world.events.reader<ActorGenerateRequest>();
    final writer = world.events.writer<ActorGenerateResponse>();

    final requests = reader.drain();
    for (final request in requests) {
      final response = await handle(request);
      writer.send(response);
    }
  }

  @override
  Future<ActorGenerateResponse> handle(ActorGenerateRequest request) async {
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    final output = responseOutput ?? {'text': responseText};

    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: output,
      rawOutput: responseText,
      toolCalls: toolCalls,
    );
  }
}

/// Helper to build a minimal world with the agent plugin and resources.
Future<World> buildTestWorld({
  ModelRouter? router,
  ToolRegistryResource? toolRegistryResource,
}) async {
  final world = World()..addPlugin(AgentPlugin());

  world
    ..upsertResource(ModelRouterResource(router ?? ModelRouter()))
    ..upsertResource(toolRegistryResource ?? ToolRegistryResource())
    ..flush();

  return world;
}

/// Helper to spawn a scene entity.
Entity spawnScene(World world) =>
    world.spawnComponents([const Scene(), SceneFrame()]);

/// Helper to spawn an actor entity in a scene.
Entity spawnActor(
  World world,
  Entity sceneEntity, {
  String systemPrompt = 'You are a helpful assistant.',
  String? openDecisionPrompt,
  SchemaBundle schema = SchemaBundle.empty,
}) {
  final actorId = AgentId.create();
  final modelId = ModelId.create();
  final components = [
    Actor(agentId: actorId),
    ActorModel(modelId: modelId),
    ActorSystemPrompt(text: systemPrompt),
    ActorRuntimeMemories(),
    PresentInScene(sceneEntity: sceneEntity),
  ];
  if (openDecisionPrompt != null) {
    components.add(OpenDecision(prompt: openDecisionPrompt, schema: schema));
  }
  return world.spawnComponents(components);
}

void main() {
  group('AgentPlugin', () {
    test('registers all components and schedules', () {
      final world = World()..addPlugin(AgentPlugin());

      // Verify schedules exist
      expect(world.hasSchedule('AgencyGrant'), isTrue);
      expect(world.hasSchedule('Project'), isTrue);
      expect(world.hasSchedule('ActorAct'), isTrue);
      expect(world.hasSchedule('ProcessResponses'), isTrue);
      expect(world.hasSchedule('Mechanical'), isTrue);
      expect(world.hasSchedule('Narrative'), isTrue);
    });

    test(
      'registers event channels for ActorGenerateRequest and ActorGenerateResponse',
      () {
        final world = World()..addPlugin(AgentPlugin());

        expect(world.events.hasRegistered<ActorGenerateRequest>(), isTrue);
        expect(world.events.hasRegistered<ActorGenerateResponse>(), isTrue);
      },
    );
  });

  group('grantAgencySystem', () {
    test('grants Agency to actors with OpenDecision', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'Decide something.',
      );
      world.flush();

      // Before: actor has no Agency
      expect(world.getEntity(actor).$2, isTrue);
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);

      world.runSchedule('AgencyGrant');
      world.flush();

      // After: actor has Agency
      final (entity, valid) = world.getEntity(actor);
      expect(valid, isTrue);
      expect(entity.has<Agency>(), isTrue);
    });

    test('does not grant Agency twice if already present', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Decide.');
      world.flush();

      // First grant
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);

      // Second grant — should not duplicate or error
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
    });

    test('does not grant Agency to actors without OpenDecision', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();

      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
    });
  });

  group('AwaitingResponse lifecycle', () {
    test('AwaitingResponse is added when actor acts', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      // Before acting: no AwaitingResponse
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);

      await world.runScheduleAsync('ActorAct');
      world.flush();

      // After acting: AwaitingResponse is present
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
    });

    test('AwaitingResponse is consumed after response is processed', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);

      await handler.processPending(world);
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();

      // After processing: AwaitingResponse is consumed
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
    });

    test('AwaitingResponse prevents re-granting Agency', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello.');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      // Actor has Agency + AwaitingResponse
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);

      // grantAgencySystem should NOT grant a second Agency
      // (it checks has<Agency>() and skips)
      world.runSchedule('AgencyGrant');
      world.flush();

      // Still has Agency (not duplicated)
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
    });
  });

  group('projectSituationSystem', () {
    test('builds a Situation for an actor with Agency', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'What is the answer?',
      );
      world.flush();

      // Grant agency first
      world.runSchedule('AgencyGrant');
      world.flush();

      // Project situation
      world.runSchedule('Project');
      world.flush();

      final (entity, valid) = world.getEntity(actor);
      expect(valid, isTrue);
      expect(entity.has<Situation>(), isTrue);

      final situation = entity.get<Situation>();
      expect(situation, isNotNull);
      expect(situation!.prompt, 'What is the answer?');
      expect(situation.inFramePropIds, isEmpty);
      expect(situation.coPresentActorIds, isEmpty);
    });

    test('includes co-present actors in Situation', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor1 = spawnActor(world, scene, openDecisionPrompt: 'Q1');
      final actor2 = spawnActor(world, scene, openDecisionPrompt: 'Q2');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      final situation1 = world.getEntity(actor1).$1.get<Situation>();
      expect(situation1, isNotNull);
      expect(situation1!.coPresentActorIds, isNotEmpty);
      expect(situation1.coPresentActorIds.length, 1);
    });

    test('includes props in frame in Situation', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      // Spawn a prop present in the scene
      final propEntity = world.spawnComponents([
        const Prop(name: 'test_file'),
        PresentProp(sceneEntity: scene),
      ]);
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      final situation = world.getEntity(actor).$1.get<Situation>();
      expect(situation, isNotNull);
      expect(situation!.inFramePropIds, contains('test_file'));
    });
  });

  group('actorActSystem', () {
    test('sends ActorGenerateRequest for actors with Agency', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');

      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'Reply with one word: hello.',
        systemPrompt: 'You are a test assistant.',
      );
      world.flush();

      // Grant agency + project situation
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();

      // Actor acts — sends request event
      await world.runScheduleAsync('ActorAct');
      world.flush();

      // Verify request was sent
      final reader = world.events.reader<ActorGenerateRequest>();
      expect(reader.isNotEmpty, isTrue);
      expect(reader.length, 1);

      final request = reader.readAt(0);
      expect(request.prompt, 'Reply with one word: hello.');
      expect(request.systemPrompt, 'You are a test assistant.');

      // Verify Agency is still present (consumed by processResponsesSystem)
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      // Verify AwaitingResponse was added
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
    });

    test('does not send requests for actors without Agency', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      // Skip AgencyGrant — actor has no Agency
      world.runSchedule('Project');
      world.flush();

      await world.runScheduleAsync('ActorAct');
      world.flush();

      final reader = world.events.reader<ActorGenerateRequest>();
      expect(reader.isEmpty, isTrue);
    });
  });

  group('processResponsesSystem', () {
    test('stores model response as context fragment', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello world');

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Say hello');
      world.flush();

      // Full loop up to actor act
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      // Process the request through the mock handler
      await handler.processPending(world);
      world.flush();

      // Process responses
      world.runSchedule('ProcessResponses');
      world.flush();

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
      expect(memories, isNotNull);
      expect(memories!.fragments, isNotEmpty);

      final lastFragment = memories.fragments.last;
      expect(lastFragment.type, ContextFragmentType.modelResponse);
      expect(lastFragment.value, contains('hello world'));

      // Verify Agency + AwaitingResponse were consumed
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
    });

    test('executes tool calls from response', () async {
      // Set up a tool registry with a mock tool
      final toolRegistry = ToolRegistry();
      final toolDef = ToolDef(
        name: ToolName('echo'),
        description: 'Echoes the input',
        parameters: const {},
        execute: (args) async => {'echoed': args},
      );
      toolRegistry.register(toolDef);

      final toolResource = ToolRegistryResource();
      toolResource.register('default', toolRegistry);

      final world = await buildTestWorld(toolRegistryResource: toolResource);
      final handler = MockActorGenerateHandler(
        responseText: 'Let me check that.',
        toolCalls: [
          ToolCall(name: ToolName('echo'), arguments: {'message': 'hello'}),
        ],
      );

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Echo hello');
      world.upsertComponent(actor, const ActorTools(registryName: 'default'));
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      await handler.processPending(world);
      world.flush();

      world.runSchedule('ProcessResponses');
      world.flush();

      // Give tool execution time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
      expect(memories, isNotNull);
      expect(memories!.fragments, isNotEmpty);

      // The last fragment should be a tool message
      final toolFragments = memories.fragments
          .where((f) => f.type == ContextFragmentType.toolMessage)
          .toList();
      expect(toolFragments, isNotEmpty);
      expect(toolFragments.first.value, contains('echoed'));
    });
  });

  group('full cinematic loop (e2e)', () {
    test('single actor end-to-end with mock LLM', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(
        responseText: 'hello',
        responseOutput: {'text': 'hello'},
      );

      final scene = spawnScene(world);
      final actor = spawnActor(
        world,
        scene,
        openDecisionPrompt: 'Reply with one short word: hello.',
      );
      world.flush();

      // 1. Grant agency
      world.runSchedule('AgencyGrant');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);

      // 2. Project situation
      world.runSchedule('Project');
      world.flush();
      expect(world.getEntity(actor).$1.has<Situation>(), isTrue);

      // 3. Actor acts (async) — adds AwaitingResponse, keeps Agency
      await world.runScheduleAsync('ActorAct');
      world.flush();
      expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);

      // 4. External handler processes requests
      await handler.processPending(world);
      world.flush();

      // 5. Process responses — consumes Agency + AwaitingResponse
      world.runSchedule('ProcessResponses');
      world.flush();

      // Verify the response was stored
      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
      expect(memories, isNotNull);
      expect(memories!.fragments, isNotEmpty);

      final lastFragment = memories.fragments.last;
      expect(lastFragment.type, ContextFragmentType.modelResponse);
      expect(lastFragment.value, contains('hello'));

      // Verify Agency + AwaitingResponse were consumed
      expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
      expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
    });

    test('multi-actor parallel end-to-end', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(
        responseText: 'response',
        responseOutput: {'text': 'response'},
      );

      final scene = spawnScene(world);

      // Spawn 3 actors with open decisions
      final actors = List.generate(
        3,
        (i) => spawnActor(
          world,
          scene,
          openDecisionPrompt: 'Actor $i: respond with a number.',
          systemPrompt: 'You are actor $i.',
        ),
      );
      world.flush();

      // 1. Grant agency to all
      world.runSchedule('AgencyGrant');
      world.flush();
      for (final actor in actors) {
        expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
      }

      // 2. Project situations
      world.runSchedule('Project');
      world.flush();
      for (final actor in actors) {
        expect(world.getEntity(actor).$1.has<Situation>(), isTrue);
      }

      // 3. All actors act concurrently — adds AwaitingResponse
      await world.runScheduleAsync('ActorAct');
      world.flush();
      for (final actor in actors) {
        expect(world.getEntity(actor).$1.has<Agency>(), isTrue);
        expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isTrue);
      }

      // 4. Handler processes all requests
      await handler.processPending(world);
      world.flush();

      // 5. Process all responses
      world.runSchedule('ProcessResponses');
      world.flush();

      // Verify all actors received responses
      for (final actor in actors) {
        final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
        expect(memories, isNotNull);
        expect(memories!.fragments, isNotEmpty);
        expect(memories.fragments.last.type, ContextFragmentType.modelResponse);
        // Verify Agency + AwaitingResponse were consumed
        expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
        expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);
      }
    });

    test(
      'agency is re-granted after acting when new OpenDecision exists',
      () async {
        final world = await buildTestWorld();
        final handler = MockActorGenerateHandler(responseText: 'done');

        final scene = spawnScene(world);
        final actor = spawnActor(
          world,
          scene,
          openDecisionPrompt: 'First decision.',
        );
        world.flush();

        // First cycle
        world.runSchedule('AgencyGrant');
        world.flush();
        world.runSchedule('Project');
        world.flush();
        await world.runScheduleAsync('ActorAct');
        world.flush();
        await handler.processPending(world);
        world.flush();
        world.runSchedule('ProcessResponses');
        world.flush();

        // Actor acted, Agency + AwaitingResponse consumed
        expect(world.getEntity(actor).$1.has<Agency>(), isFalse);
        expect(world.getEntity(actor).$1.has<AwaitingResponse>(), isFalse);

        // Add a new OpenDecision
        world.upsertComponent(
          actor,
          const OpenDecision(prompt: 'Second decision.'),
        );
        world.flush();

        // Second cycle — agency should be granted again
        world.runSchedule('AgencyGrant');
        world.flush();
        expect(world.getEntity(actor).$1.has<Agency>(), isTrue);

        world.runSchedule('Project');
        world.flush();
        await world.runScheduleAsync('ActorAct');
        world.flush();
        await handler.processPending(world);
        world.flush();
        world.runSchedule('ProcessResponses');
        world.flush();

        final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
        expect(memories, isNotNull);
        expect(memories!.fragments.length, 2);
      },
    );
  });

  group('Thread scoring and pruning', () {
    test('scoreThreadsSystem assigns scores to threads', () async {
      final world = await buildTestWorld();

      final thread1 = world.spawnComponents([const Thread(), ThreadScore(0.0)]);
      final thread2 = world.spawnComponents([const Thread(), ThreadScore(0.0)]);
      world.flush();

      world.runSchedule('Mechanical');
      world.flush();

      // With no beats, score should be 0.0
      expect(world.getEntity(thread1).$1.get<ThreadScore>()?.value, 0.0);
      expect(world.getEntity(thread2).$1.get<ThreadScore>()?.value, 0.0);
    });

    test('pruneThreadsSystem marks low-scoring threads as pruned', () async {
      final world = await buildTestWorld();

      final highScoreThread = world.spawnComponents([
        const Thread(),
        ThreadScore(0.5),
        ThreadStatus(ThreadStatusEnum.active),
      ]);
      final lowScoreThread = world.spawnComponents([
        const Thread(),
        ThreadScore(0.05),
        ThreadStatus(ThreadStatusEnum.active),
      ]);
      world.flush();

      // Run pruneThreadsSystem directly (not the full Mechanical schedule,
      // since scoreThreadsSystem would overwrite scores)
      pruneThreadsSystem(world);
      world.flush();

      // High-score thread survives (still active)
      expect(world.getEntity(highScoreThread).$2, isTrue);
      expect(
        world.getEntity(highScoreThread).$1.get<ThreadStatus>()?.value,
        ThreadStatusEnum.active,
      );
      // Low-score thread is marked as pruned (not despawned)
      expect(world.getEntity(lowScoreThread).$2, isTrue);
      expect(
        world.getEntity(lowScoreThread).$1.get<ThreadStatus>()?.value,
        ThreadStatusEnum.pruned,
      );
    });
  });

  group('Narrative systems', () {
    test('spawnThread creates a Thread with status and score', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      final thread = spawnThread(world, actor, scene);
      world.flush();

      expect(world.getEntity(thread).$2, isTrue);
      expect(
        world.getEntity(thread).$1.get<ThreadStatus>()?.value,
        ThreadStatusEnum.active,
      );
      expect(world.getEntity(thread).$1.get<ThreadScore>()?.value, 0.0);
      expect(world.getEntity(thread).$1.get<OriginActor>()?.actor, actor);
      expect(world.getEntity(thread).$1.get<ParentScene>()?.scene, scene);
    });

    test('startBeat creates a Beat in partial status', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.flush();

      final beat = startBeat(world, thread, actor, BeatModalityEnum.text);
      world.flush();

      expect(world.getEntity(beat).$2, isTrue);
      expect(
        world.getEntity(beat).$1.get<BeatStatus>()?.value,
        BeatStatusEnum.partial,
      );
      expect(
        world.getEntity(beat).$1.get<BeatModality>()?.value,
        BeatModalityEnum.text,
      );
      expect(world.getEntity(beat).$1.get<BelongsToThread>()?.thread, thread);
      expect(world.getEntity(beat).$1.get<Speaker>()?.actor, actor);
    });

    test('appendToBeat adds chunks to TextStream', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.flush();

      final beat = startBeat(
        world,
        thread,
        actor,
        BeatModalityEnum.streamingText,
      );
      world.flush();

      appendToBeat(world, beat, 'Hello');
      appendToBeat(world, beat, ' world');
      world.flush();

      final stream = world.getEntity(beat).$1.get<TextStream>();
      expect(stream, isNotNull);
      expect(stream!.chunks, ['Hello', ' world']);
    });

    test('completeBeat finalizes a partial Beat', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.flush();

      final beat = startBeat(
        world,
        thread,
        actor,
        BeatModalityEnum.streamingText,
      );
      world.flush();

      appendToBeat(world, beat, 'Hello');
      appendToBeat(world, beat, ' world');
      world.flush();

      completeBeat(world, beat);
      world.flush();

      expect(
        world.getEntity(beat).$1.get<BeatStatus>()?.value,
        BeatStatusEnum.complete,
      );
      expect(world.getEntity(beat).$1.get<TextContent>()?.text, 'Hello world');
      expect(world.getEntity(beat).$1.get<TextStream>(), isNull);
    });

    test('finalizePartialsSystem completes Beats with full cursor', () async {
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      final thread = spawnThread(world, actor, scene);
      world.flush();

      final beat = startBeat(
        world,
        thread,
        actor,
        BeatModalityEnum.streamingText,
      );
      world.flush();

      appendToBeat(world, beat, 'Hello');
      world.flush();

      // Move cursor to end
      final stream = world.getEntity(beat).$1.get<TextStream>();
      stream!.cursor = stream.chunks.length;
      world.flush();

      world.runSchedule('Narrative');
      world.flush();

      expect(
        world.getEntity(beat).$1.get<BeatStatus>()?.value,
        BeatStatusEnum.complete,
      );
      expect(world.getEntity(beat).$1.get<TextContent>()?.text, 'Hello');
    });
  });

  group('HarnessLoop idle/sleep', () {
    test('canSleep returns true when no work remains', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');
      final loop = HarnessLoop(world: world, handler: handler);

      // No actors, no decisions, no agency — should be able to sleep
      expect(loop.canSleep(), isTrue);
    });

    test('canSleep returns false when OpenDecision exists', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');
      final loop = HarnessLoop(world: world, handler: handler);

      final scene = spawnScene(world);
      spawnActor(world, scene, openDecisionPrompt: 'Decide something.');
      world.flush();

      expect(loop.canSleep(), isFalse);
    });

    test('canSleep returns false when Agency exists', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');
      final loop = HarnessLoop(world: world, handler: handler);

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();

      expect(loop.canSleep(), isFalse);
    });

    test('canSleep returns false when AwaitingResponse exists', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');
      final loop = HarnessLoop(world: world, handler: handler);

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      expect(loop.canSleep(), isFalse);
    });

    test('canSleep returns true after response is processed', () async {
      final world = await buildTestWorld();
      final handler = MockActorGenerateHandler(responseText: 'hello');
      final loop = HarnessLoop(world: world, handler: handler);

      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'Q');
      world.flush();

      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();

      expect(loop.canSleep(), isFalse);

      await handler.processPending(world);
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();

      expect(loop.canSleep(), isTrue);
    });
  });

  group('ModelRouterResource', () {
    test('wraps a ModelRouter and is retrievable', () {
      final world = World()..addPlugin(AgentPlugin());
      final router = ModelRouter();
      world.upsertResource(ModelRouterResource(router));
      world.flush();

      final resource = world.getResource<ModelRouterResource>();
      expect(resource.router, same(router));
    });
  });

  group('ToolRegistryResource', () {
    test('registers and retrieves named tool registries', () {
      final resource = ToolRegistryResource();
      final registry = ToolRegistry();
      resource.register('default', registry);

      expect(resource.get('default'), same(registry));
      expect(resource.get('nonexistent'), isNull);
    });
  });

  group('ContextFragment', () {
    test('holds type and value', () {
      const fragment = ContextFragment(
        type: ContextFragmentType.userMessage,
        value: 'hello',
      );
      expect(fragment.type, ContextFragmentType.userMessage);
      expect(fragment.value, 'hello');
    });
  });

  group('ActorGenerateRequest', () {
    test('carries all fields needed for LLM generation', () {
      final entity = Entity.create(1);
      final request = ActorGenerateRequest(
        actorEntity: entity,
        agentId: const AgentId('agent-1'),
        modelId: const ModelId('model-1'),
        prompt: 'What is 2+2?',
        systemPrompt: 'You are a calculator.',
        contextFragments: ['systemPrompt:You are a calculator.'],
        schema: SchemaBundle.empty,
        toolRegistry: null,
        task: InferenceTask.text,
      );

      expect(request.actorEntity, entity);
      expect(request.agentId.value, 'agent-1');
      expect(request.modelId.value, 'model-1');
      expect(request.prompt, 'What is 2+2?');
      expect(request.systemPrompt, 'You are a calculator.');
      expect(request.contextFragments, ['systemPrompt:You are a calculator.']);
      expect(request.schema, SchemaBundle.empty);
      expect(request.toolRegistry, isNull);
      expect(request.task, InferenceTask.text);
    });
  });

  group('ActorGenerateResponse', () {
    test('carries output, rawOutput, and toolCalls', () {
      final entity = Entity.create(1);
      final response = ActorGenerateResponse(
        actorEntity: entity,
        structuralOutput: {'text': '4'},
        rawOutput: '4',
        toolCalls: [
          ToolCall(name: ToolName('calc'), arguments: {'expr': '2+2'}),
        ],
      );

      expect(response.actorEntity, entity);
      expect(response.structuralOutput, {'text': '4'});
      expect(response.rawOutput, '4');
      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.name.value, 'calc');
      expect(response.toolCalls.first.arguments, {'expr': '2+2'});
    });
  });

  group('ToolCall', () {
    test('holds name and arguments', () {
      final call = ToolCall(
        name: ToolName('search'),
        arguments: {'query': 'weather'},
      );
      expect(call.name.value, 'search');
      expect(call.arguments, {'query': 'weather'});
    });
  });
}
