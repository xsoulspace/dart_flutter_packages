# ADR 0062: Write-ahead live-apply recovery and restartable inverse

- Status: Accepted
- Date: 2026-10-11
- North Star impact: applies — qualifies existing storage recovery, no replication or harness ownership change
- Decision maker: operator authorization to reproduce/fix recovery before integration

## Context

Five fault controls failed on the original live-apply package: empty writes
could not roll back, deleting an empty post-state bypassed drift detection,
an effect before post journaling was unrecoverable, the provider wrapper pruned
the journal after an effectful exception, and interrupted inverse replay could
not resume. The last three violate the existing crash-recovery intent.

## Options

Keep post-only journaling (unsafe), add another transaction engine (duplicates
ownership), or strengthen the existing footprint journal (chosen).

## Decision

Journal schema v2 separates presence from content hash. Persist pre-operation
and intended post-operation states before invoking the provider. Pending effects
admit either recognized state during rollback and refuse unexplained drift.
Record rollingBack and per-path inverse-started/restored progress before/after
the inverse; verify presence or content after every restoration, including
removal of created files. Reopened handles reload the durable journal before
mutating, so a stale handle cannot bypass finalized or interrupted state.

Use the retained store lock inode for cooperating process exclusion and an
in-process guard for overlapping calls. Lock the entire read/check/journal/effect
operation, including rollback preflight and replay. The host must still exclude
writers bypassing this store; this is not provider compare-and-swap, a distributed
lock, multi-isolate certification or arbitrary concurrent CRDT rollback.

The wrapper keeps failed-operation journals unless locked read-back proves the
whole footprint unchanged. Create/update/delete still call the corresponding
provider operation; append keeps its native provider operation. Finalization
persists committed before pruning. Apply retains undo; commit closes it.

Unversioned journals with an empty/deletion sentinel are ambiguous and refuse
with a named reason without mutation. Unambiguous v1 journals remain readable,
but missing write-ahead evidence cannot be reconstructed. Unknown versions and
lifecycle values refuse. Post-only recordPost is retained as a deprecated API
that refuses; direct users migrate to mutate(path, intendedContent, effect),
which declares a single-path effect before dispatch.

## Consequences and qualification

Additional journal writes buy bounded recovery checkpoints. Whole-batch live
visibility is unchanged: rollback is recoverable, not atomically invisible to
readers. Journal rename provides publication atomicity; abrupt process tests do
not establish storage-hardware power-loss/fsync guarantees. Recognized hashes
cannot establish authorship when an external writer produces identical bytes.

Qualification includes effect-boundary faults, interrupted inverse, empty versus
absent state, provider failures, failed deletion, drift, stale handles, legacy
refusals, and competing writers. Harness integration remains gated separately
by harness ADR 0089 and its MEAN roadmap.
