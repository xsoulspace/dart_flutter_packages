// ignore_for_file: lines_longer_than_80_chars

/// Thread lifecycle — scoring, pruning, merging.
///
/// Threads are scoreable narrative branches. `scoreThreadsSystem` assigns
/// scores, `pruneThreadsSystem` marks low-scoring threads `pruned` (kept for
/// history, excluded from projection), and merge re-parents beats. These are
/// mechanical systems that never touch an LLM.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/src/agent/schedules.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('scoreThreadsSystem', () {
    test('with no beats keeps a score of 0.0', () async {
      final world = await buildTestWorld();

      world.spawnComponents([const Thread(), ThreadScore(0.0)]);
      world.spawnComponents([const Thread(), ThreadScore(0.0)]);
      world.flush();

      world.runSchedule(Schedules.mechanical);
      world.flush();

      final threads = world.query2<Thread, ThreadScore>().toList();
      expect(threads, hasLength(2));
      for (final (_, _, score) in threads) {
        expect(score.value, 0.0);
      }
    });
  });

  group('pruneThreadsSystem', () {
    test(
      'marks low-scoring threads as pruned and leaves high ones active',
      () async {
        final world = await buildTestWorld();

        final high = world.spawnComponents([
          const Thread(),
          ThreadScore(0.5),
          ThreadStatus(ThreadStatusEnum.active),
        ]);
        final low = world.spawnComponents([
          const Thread(),
          ThreadScore(0.05),
          ThreadStatus(ThreadStatusEnum.active),
        ]);
        world.flush();

        // Run the prune system directly (not the Mechanical schedule, which
        // would overwrite the manually set scores).
        pruneThreadsSystem(world);
        world.flush();

        expect(
          world.getEntity(high).$1.get<ThreadStatus>()?.value,
          ThreadStatusEnum.active,
        );
        expect(
          world.getEntity(low).$1.get<ThreadStatus>()?.value,
          ThreadStatusEnum.pruned,
        );
      },
    );
  });
}
