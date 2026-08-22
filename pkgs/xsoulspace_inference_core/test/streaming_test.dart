// ignore_for_file: lines_longer_than_80_chars

/// Text streaming through the harness: deltas land in StreamingBeat AND on
/// the StreamingTapResource push channel; the final response is unchanged.

import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// A handler that emits deltas before the final response.
class _StreamingMockHandler implements GenerationHandler {
  _StreamingMockHandler({required this.deltas});

  final List<String> deltas;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final tap = world.getResource<StreamingTapResource>();
    for (final delta in deltas) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      world.events.writer<ActorGenerateStreamEvent>().send(
        ActorGenerateStreamEvent(
          actorEntity: request.actorEntity,
          taskId: request.taskId,
          chunk: delta,
        ),
      );
      tap.publish(request.actorEntity, delta);
    }
    final text = deltas.join();
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': text},
      rawOutput: text,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test(
    'streaming deltas accumulate in StreamingBeat and close the tap',
    () async {
      final handler = _StreamingMockHandler(deltas: ['Hello', ' ', 'world']);
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene, openDecisionPrompt: 'greet');
      world.flush();

      // Subscribe to the push channel BEFORE driving the cycle.
      final received = <String>[];
      var tapClosed = false;
      final sub = world
          .getResource<StreamingTapResource>()
          .subscribe(actor)
          .listen(received.add, onDone: () => tapClosed = true);

      // Full cinematic cycle so agency is granted and projection runs.
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      // Let the async handler finish emitting deltas + response.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();

      // Deltas accumulated into the actor's StreamingBeat.
      final beat = world.getEntity(actor).$1.get<StreamingBeat>();
      expect(beat, isNotNull);
      expect(beat!.chunks.join(), 'Hello world');

      // Push channel delivered every delta and closed at end of turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received.join(), 'Hello world');
      expect(tapClosed, isTrue);

      await sub.cancel();
    },
  );

  test('tap publish with no subscribers is a no-op', () async {
    final handler = _StreamingMockHandler(deltas: ['x']);
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene, openDecisionPrompt: 'go');
    world.flush();

    // No subscribe() — publishing must not throw.
    world.runSchedule('AgencyGrant');
    world.flush();
    world.runSchedule('Project');
    world.flush();
    await world.runScheduleAsync('ActorAct');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    world.flush();
    world.runSchedule('ProcessResponses');
    world.flush();

    expect(world.getEntity(actor).$1.has<OpenDecision>(), isFalse);
  });

  test('ModelRuntime.generate streams when client supports it', () async {
    // A fake streaming client proving ModelRuntime forwards onDelta.
    final runtime = ModelRuntime(
      model: const Model(id: ModelId('m')),
      client: _FakeStreamingClient(),
    );
    final deltas = <String>[];
    final response = await runtime.generate(
      prompt: 'hi',
      systemPrompt: '',
      contextFragments: const [],
      outputSchema: SchemaBundle.empty,
      toolRegistry: null,
      task: InferenceTask.text,
      onDelta: deltas.add,
    );
    expect(deltas.join(), 'abc');
    expect(response?.rawOutput, 'abc');
  });
}

/// Minimal InferenceClient that fakes structured-text streaming.
class _FakeStreamingClient implements StructuredTextStreamingInferenceClient {
  @override
  String get id => 'fake_stream';
  @override
  bool get isAvailable => true;
  @override
  Set<InferenceTask> get supportedTasks => const {InferenceTask.text};
  @override
  Future<bool> refreshAvailability() async => true;
  @override
  Future<void> load() async {}
  @override
  void resetAvailabilityCache() {}

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async => InferenceResult<InferenceResponse>.fail(
    code: 'not_used',
    message: 'streaming path should be taken',
  );

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    InferenceRequest request,
  ) async {
    final controller = StreamController<InferenceStructuredTextStreamEvent>();
    for (final chunk in ['a', 'b', 'c']) {
      controller.add(
        InferenceStructuredTextStreamEvent(
          type: .partialOutput,
          timestamp: DateTime.now(),
          textDelta: chunk,
        ),
      );
    }
    unawaited(controller.close());
    return _FakeSession(events: controller.stream);
  }
}

class _FakeSession implements InferenceStructuredTextStreamSession {
  _FakeSession({required this.events});
  @override
  final Stream<InferenceStructuredTextStreamEvent> events;

  @override
  Future<InferenceResult<InferenceResponse>> get result async =>
      InferenceResult<InferenceResponse>.ok(
        InferenceResponse(rawOutput: 'abc'),
      );

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}
