// ignore_for_file: lines_longer_than_80_chars

/// CLI/server ergonomics: the fs-tools path jail and `HarnessLoop.runUntilIdle`.

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

/// A handler that re-opens the actor's decision on every response —
/// simulates a world that never goes idle (for the maxTicks guard test).
class _SelfPerpetuatingHandler implements GenerationHandler {
  _SelfPerpetuatingHandler({required this.actor, required this.world});
  final Entity actor;
  final World world;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'still working'},
      rawOutput: 'still working',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    // Re-open the decision after it is consumed by ProcessResponses.
    Future<void>.delayed(Duration.zero).then((_) {
      world.upsertComponent(actor, OpenDecision(prompt: 'loop forever'));
      world.flush();
    });
    return response;
  }
}

void main() {
  group('fs tools path jail', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('ecsly_fs_jail');
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('write and read inside the root works', () async {
      final tools = fsTools(FsToolsRoot(root.path));
      final write = tools.firstWhere((t) => t.name.value == 'write');
      final read = tools.firstWhere((t) => t.name.value == 'read');

      await write.execute({'path': 'notes.txt', 'content': 'hello'});
      final content = await read.execute({'path': 'notes.txt'}) as String;
      expect(content, 'hello');
    });

    test('relative paths resolve against the root', () async {
      final tools = fsTools(FsToolsRoot(root.path));
      final listDir = tools.firstWhere((t) => t.name.value == 'list_dir');

      Directory('${root.path}/sub').createSync();
      final entries = await listDir.execute({'path': '.'}) as String;
      expect(entries, contains('sub'));
    });

    test('absolute paths inside the root are allowed', () async {
      final tools = fsTools(FsToolsRoot(root.path));
      final read = tools.firstWhere((t) => t.name.value == 'read');

      File('${root.path}/a.txt').writeAsStringSync('x');
      expect(await read.execute({'path': '${root.path}/a.txt'}), 'x');
    });

    test('traversal outside the root is rejected', () async {
      final tools = fsTools(FsToolsRoot('${root.path}/jail'));
      final read = tools.firstWhere((t) => t.name.value == 'read');
      final write = tools.firstWhere((t) => t.name.value == 'write');

      // The jail root exists; escaping via .. must fail on every tool.
      // readTool throws synchronously (before returning a Future), so use a
      // closure matcher rather than expectLater on the returned future.
      expect(
        () => read.execute({'path': '../../etc/passwd'}),
        throwsArgumentError,
      );
      expect(
        () => write.execute({'path': '../escape.txt', 'content': 'x'}),
        throwsArgumentError,
      );
    });
  });

  group('HarnessLoop.runUntilIdle', () {
    test('drives a full decision cycle and returns when idle', () async {
      final handler = MockGenerationHandler(responseText: 'cli answer');
      final world = await buildTestWorld(handler: handler);
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.flush();

      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.upsertComponent(actor, OpenDecision(prompt: 'hello'));
      world.flush();

      final loop = HarnessLoop(world: world);
      await loop.runUntilIdle();

      // Decision consumed, response beat written.
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isFalse);
      expect(beatsWithText(world, 'cli answer'), hasLength(1));
      expect(loop.canSleep(), isTrue);
    });

    test('maxTicks guard throws on a world that never goes idle', () async {
      // A self-perpetuating actor: every response immediately opens a new
      // decision, so the world never goes idle and the guard must trip.
      final world = await buildTestWorld();
      final scene = spawnScene(world);
      final actor = spawnActor(world, scene);
      world.getResource<GenerationHandlerResource>().registerDefault(
        _SelfPerpetuatingHandler(actor: actor, world: world),
      );
      world.flush();

      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.upsertComponent(actor, OpenDecision(prompt: 'loop forever'));
      world.flush();

      final loop = HarnessLoop(world: world);
      await expectLater(loop.runUntilIdle(maxTicks: 5), throwsStateError);
    });
  });
}
