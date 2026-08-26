import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

class _DelayedHandler implements GenerationHandler {
  final Completer<ActorGenerateRequest> started = Completer();

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (!started.isCompleted) started.complete(request);
    await Completer<void>().future;
    throw StateError('handler was cancelled before completing');
  }
}

class _StreamingHandler implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    const text = 'Hello world';
    for (final chunk in ['Hello', ' ', 'world']) {
      world.events.writer<ActorGenerateStreamEvent>().send(
        ActorGenerateStreamEvent(
          actorEntity: request.actorEntity,
          taskId: request.taskId,
          chunk: chunk,
        ),
      );
      world.getResource<StreamingTapResource>().publish(
        request.actorEntity,
        chunk,
      );
      world.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': text},
      rawOutput: text,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

CliHost buildCliTestHost(
  World world, {
  required ToolConfirmationCallback confirmation,
  CliHostConfig config = const CliHostConfig(),
}) => CliHost(
  world: world,
  config: config,
  requestToolConfirmation: confirmation,
);

void main() {
  test('feed opens a decision while idle and produces output', () async {
    final world = await buildTestWorld(handler: _StreamingHandler());
    final scene = spawnScene(world);
    spawnActor(world, scene);
    final host = buildCliTestHost(world, confirmation: (_, _) async => true);
    unawaited(host.start());
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(host.feed('Say hello'), isTrue);
    final chunks = await host.output.take(3).toList();
    expect(chunks.join(), 'Hello world');

    await host.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('cancel releases agency and clears tasks', () async {
    final handler = _DelayedHandler();
    final world = await buildTestWorld(handler: handler);
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final host = buildCliTestHost(world, confirmation: (_, _) async => true);
    unawaited(host.start());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(host.feed('long task'), isTrue);

    await handler.started.future;
    final idle = host.waitForIdle();
    host.cancel();
    await idle.timeout(const Duration(seconds: 1));

    final entity = world.getEntity(actor).$1;
    expect(entity.has<Agency>(), isFalse);
    expect(entity.has<AwaitingResponse>(), isFalse);
    expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);

    await host.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('inspectSituation returns projected situations', () async {
    final world = await buildTestWorld(handler: _DelayedHandler());
    final scene = spawnScene(world);
    final actor = spawnActor(world, scene);
    world.flush();
    final host = buildCliTestHost(world, confirmation: (_, _) async => true);
    unawaited(host.start());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    host.feed('inspect me');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final situations = host.inspectSituation();
    expect(situations, containsPair(actor, isA<Situation>()));

    host.cancel();
    await host.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('confirmation gate blocks and rejects protected tools', () async {
    final requests = <String>[];
    final confirmations = <Completer<bool>>[];
    var executed = false;
    final registry = ToolRegistry()
      ..register(
        ToolDef.encode(
          name: const ToolName('dangerous'),
          description: 'dangerous',
          execute: (_) async {
            executed = true;
            return {'ok': true};
          },
        ),
      );
    final tools = ToolRegistryResource()..register('default', registry);
    final world = World()..addPlugin(AgentPlugin());
    world
      ..upsertResource(ModelRouterResource(ModelRouter()))
      ..upsertResource(tools)
      ..flush();

    final cliHost = CliHost(
      world: world,
      config: const CliHostConfig(confirmationRequiredTools: {'dangerous'}),
      requestToolConfirmation: (name, arguments) {
        requests.add('${name.value}:${jsonEncode(arguments)}');
        final completer = Completer<bool>();
        confirmations.add(completer);
        return completer.future;
      },
    );

    final guardedRegistry = cliHost.world
        .getResource<ToolRegistryResource>()
        .get('default')!;
    final execution = guardedRegistry.execute(const ToolName('dangerous'), {
      'value': 'ok',
    });
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(executed, isFalse);
    expect(requests, ['dangerous:{"value":"ok"}']);

    confirmations[0].complete(false);
    expect(await execution, contains('rejected'));
    expect(executed, isFalse);

    final secondExecution = guardedRegistry.execute(
      const ToolName('dangerous'),
      {'value': 'again'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(executed, isFalse);
    expect(requests.length, 2);

    confirmations[1].complete(true);
    await secondExecution;
    expect(executed, isTrue);
  });

  group('renderSituation', () {
    test("shows '(idle)' before any turn", () async {
      final world = await buildTestWorld(handler: _StreamingHandler());
      final scene = spawnScene(world);
      spawnActor(world, scene);
      final host = buildCliTestHost(world, confirmation: (_, _) async => true);
      unawaited(host.start());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(host.renderSituation(), '(idle)');

      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('renders agent id, token count, and modality tags mid-turn', () async {
      final world = await buildTestWorld(handler: _DelayedHandler());
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();
      final thread = world.spawnComponents([const Thread()]);
      world.flush();
      addIndexedBeat(world, thread, actor, 'previously established context', [
        'context',
      ]);
      final host = buildCliTestHost(world, confirmation: (_, _) async => true);
      unawaited(host.start());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      host.feed('recall the context');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final agentId =
          world.getEntity(actor).$1.get<Actor>()?.agentId.value ?? '';
      final rendered = host.renderSituation();
      expect(rendered, contains('actor $agentId'));
      expect(rendered, contains('tokens='));
      expect(rendered, contains('beats='));
      expect(rendered, contains('[text]'));

      host.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(host.renderSituation(), '(idle)');

      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });

  group('onIdleTurnEnd', () {
    test('fires exactly once per feed→waitForIdle cycle', () async {
      var turns = 0;
      final world = await buildTestWorld(
        handler: MockGenerationHandler(responseText: 'done'),
      );
      final scene = spawnScene(world);
      spawnActor(world, scene);
      final host = buildCliTestHost(
        world,
        confirmation: (_, _) async => true,
        config: CliHostConfig(onIdleTurnEnd: () async => turns++),
      );
      unawaited(host.start());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(turns, isZero, reason: 'quiet startup is not a turn');

      expect(host.feed('one'), isTrue);
      await host.waitForIdle();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(turns, 1);

      expect(host.feed('two'), isTrue);
      await host.waitForIdle();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(turns, 2);

      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('callback errors do not break subsequent turns', () async {
      var calls = 0;
      final world = await buildTestWorld(
        handler: MockGenerationHandler(responseText: 'done'),
      );
      final scene = spawnScene(world);
      spawnActor(world, scene);
      final host = buildCliTestHost(
        world,
        confirmation: (_, _) async => true,
        config: CliHostConfig(
          onIdleTurnEnd: () async {
            calls++;
            // Simulate a real autosave failing after an await boundary.
            await Future<void>.delayed(Duration.zero);
            throw StateError('autosave failed');
          },
        ),
      );
      unawaited(host.start());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(host.feed('boom'), isTrue);
      await host.waitForIdle();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 1);

      expect(host.feed('again'), isTrue);
      await host.waitForIdle();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 2, reason: 'second turn completed despite autosave error');
      expect(host.isRunning, isTrue);

      await host.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
