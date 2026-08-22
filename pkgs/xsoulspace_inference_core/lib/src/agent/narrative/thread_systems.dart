import 'package:ecsly/ecsly.dart';

import 'components.dart';

/// Thread scoring, pruning, and merging systems.
library;

/// Real scoring system — scores Threads based on heuristics.
///
/// Scoring factors:
/// - Number of Complete Beats
/// - Average Beat score (if present)
/// - Goal relevance (if GoalLink exists)
/// - Recency of activity
void scoreThreadsSystem(World w) {
  final index = w.getResource<FacetIndex>();
  final threads = w.query2<Thread, ThreadScore>();
  for (final (entity, _, score) in threads) {
    // O(beats-in-thread) via the index — no full-world scan per thread.
    final beatCount = index.beatsOfThread(entity.entity).length;
    // Simple heuristic: more complete beats = higher score
    score.value = (beatCount * 0.1).clamp(0.0, 1.0);
  }
}

/// Prune low-scoring Threads — marks as `pruned` instead of despawning.
///
/// Pruned Threads remain queryable for history but are excluded from
/// normal projection.
void pruneThreadsSystem(World w) {
  final threads = w.query2<Thread, ThreadScore>();
  for (final (entity, _, score) in threads.toList()) {
    if (score.value < 0.1) {
      final status = entity.get<ThreadStatus>();
      if (status != null && status.value != ThreadStatusEnum.pruned) {
        status.value = ThreadStatusEnum.pruned;
        // Deindex the thread's beats so projection cannot ray-trace into
        // pruned history via stale keyword hits.
        deindexThreadBeats(w, entity.entity);
      }
    }
  }
}

void deindexThreadBeats(World w, Entity thread) {
  for (final beat in w.getResource<FacetIndex>().beatsOfThread(thread).toList()) {
    deindexBeat(w, beat);
  }
}

/// Merge low-value Threads into higher-value ones.
///
/// Re-parents Beats from source Thread to target Thread.
void mergeThreadsSystem(World w) {
  final pruned = w.query2<Thread, ThreadStatus>().where(
    (t) => t.$3.value == ThreadStatusEnum.pruned,
  );
  for (final (entity, _, status) in pruned) {
    // Find a target Thread to merge into (same Scene, higher score)
    final sourceScene = entity.get<ParentScene>();
    if (sourceScene == null) continue;

    final candidates = w.query3<Thread, ThreadScore, ParentScene>().where(
      (t) =>
          t.$4.scene == sourceScene.scene && t.$3.value > 0.1 && t.$1 != entity,
    );
    if (candidates.isEmpty) continue;

    // Pick the highest-scoring candidate
    final target = candidates
        .fold(
          candidates.first,
          (best, curr) => curr.$3.value > best.$3.value ? curr : best,
        )
        .$1;

    // Re-parent all Beats (the target keeps its index entries; the source's
    // beats were already deindexed when it was pruned — re-index them under
    // the merged thread is a no-op for the index, only ownership changes).
    final index = w.getResource<FacetIndex>();
    for (final beat in index.beatsOfThread(entity.entity).toList()) {
      w.getEntity(beat).$1.insert(BelongsToThread(target.entity));
      index.moveBeatToThread(beat, entity.entity, target.entity);
    }

    // Mark source as merged
    status.value = ThreadStatusEnum.merged;
  }
}
