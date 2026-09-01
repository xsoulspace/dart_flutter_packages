// ignore_for_file: lines_longer_than_80_chars

/// Narrative graph tests — the graph-native thread/beat primitives.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('spawnThread', () {
    test(
      'creates a Thread with active status, zero score, origin, and scene',
      () async {
        final world = await buildTestWorld();
        final scene = spawnScene(world);
        final actor = spawnActor(world, scene);
        world.flush();
        final thread = spawnThread(world, actor, scene);
        world.flush();

        final (entity, valid) = world.getEntity(thread);
        expect(valid, isTrue);
        expect(entity.get<ThreadStatus>()?.value, ThreadStatusEnum.active);
        expect(entity.get<ThreadScore>()?.value, 0.0);
        expect(entity.get<OriginActor>()?.actor, actor);
        expect(entity.get<ParentScene>()?.scene, scene);
      },
    );
  });

  group('startBeat', () {
    test('creates a partial Beat with speaker, thread, and sequence', () async {
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
  });

  group('appendToBeat / completeBeat', () {
    test('append adds chunks to the TextStream', () async {
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
      appendToBeat(world, beat, 'Hello');
      appendToBeat(world, beat, ' world');
      world.flush();

      final stream = world.getEntity(beat).$1.get<TextStream>();
      expect(stream?.chunks, ['Hello', ' world']);
    });

    test(
      'completeBeat finalizes into TextContent and removes the stream',
      () async {
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
        appendToBeat(world, beat, 'Hello');
        appendToBeat(world, beat, ' world');
        completeBeat(world, beat);
        world.flush();

        expect(
          world.getEntity(beat).$1.get<BeatStatus>()?.value,
          BeatStatusEnum.complete,
        );
        expect(
          world.getEntity(beat).$1.get<TextContent>()?.text,
          'Hello world',
        );
        expect(world.getEntity(beat).$1.get<TextStream>(), isNull);
      },
    );
  });

  group('finalizePartialsSystem', () {
    test('completes Beats whose cursor reached the end', () async {
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
      appendToBeat(world, beat, 'Hello');
      world.flush();

      final stream = world.getEntity(beat).$1.get<TextStream>()!;
      stream.cursor = stream.chunks.length;
      world.flush();

      world.runSchedule(Schedules.narrative);
      world.flush();

      expect(
        world.getEntity(beat).$1.get<BeatStatus>()?.value,
        BeatStatusEnum.complete,
      );
      expect(world.getEntity(beat).$1.get<TextContent>()?.text, 'Hello');
    });
  });
}
