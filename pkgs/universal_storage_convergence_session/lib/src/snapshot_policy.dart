/// Generic compaction policy for an anti-entropy replica: when the pending
/// op log should fold into state.
///
/// Two triggers, whichever fires first:
///
/// - **Size** — the log grew past [maxLogOps];
/// - **Age** — the log is non-empty and [minInterval] elapsed since the
///   owner's last compaction.
///
/// The policy itself is pure: the owner (typically the anti-entropy
/// session driver) tracks `lastCompactionAt` and passes it in. An empty
/// log never compacts — there is nothing to retire. Passing `null` for a
/// trigger disables it, so parents can run size-only or interval-only
/// policies without subclasses.
///
/// Provenance: extracted from ecsly's
/// `plugins/ecsly_world_sync_bridge` `SnapshotPolicy` so mesh sync and
/// ecsly world sync share one type; the VALUES stay parent-chosen — each
/// parent passes its own thresholds and keeps its own clock.
library;

/// Default log-length trigger.
const int defaultMaxLogOps = 512;

/// Default compaction interval.
const Duration defaultMinInterval = Duration(minutes: 5);

/// Whether a replica with a pending log of [logLength] ops should compact
/// now.
///
/// [lastCompactionAt] is the owner's last compaction timestamp; `null`
/// means "never compacted by this owner", in which case only the size
/// trigger can fire (there is no interval to have elapsed yet).
/// [maxLogOps] / [minInterval] default to the shared 512-ops / 5-minutes
/// defaults; `null` disables that trigger entirely.
bool shouldCompact({
  required final int logLength,
  required final DateTime now,
  final DateTime? lastCompactionAt,
  final int? maxLogOps = defaultMaxLogOps,
  final Duration? minInterval = defaultMinInterval,
}) {
  if (maxLogOps != null && logLength > maxLogOps) return true;
  if (logLength == 0) return false;
  if (minInterval == null) return false;
  final since = lastCompactionAt == null
      ? null
      : now.difference(lastCompactionAt);
  return since != null && since >= minInterval;
}
