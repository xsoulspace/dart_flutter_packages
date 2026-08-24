# ADR 0011: Convergence kernel — dual mode (op log + snapshots) shared by mesh and ecsly

- Status: Accepted
- Date: 2026-08-24
- North Star impact: `sub_star`
- Builds on: [0007](0007_extensibility_seams_and_conformance.md), [0009](0009_goals_as_vectors_plans_as_projections.md) (projection discipline)
- Related: [0010](0010_mesh_sync_architecture.md) (primary consumer)

## Context

Three systems in this ecosystem keep rediscovering the same shape:

| System | Deltas | Derived state |
| --- | --- | --- |
| Agentic harness | beats | projections (memory is projection over beat-threads, never a log) |
| Games (industry practice) | input/command log + checkpoints | world state = replay(checkpoint, commands) |
| Multiplayer docs (Notion, Zed, Figma) | CRDT ops + snapshots | document state = fold(snapshot, ops) |

Mesh storage sync ([0010](0010_mesh_sync_architecture.md)) needs convergence;
ecsly multiplayer needs the same. The user-facing argument that settled this:
multiplayer is a usability win for *any* stateful app — a note app is
multiplayer like Zed; a game session continuing from phone to web is the same
problem as a friend joining mid-game. One kernel should serve all of them,
outside both consumers.

Prior discussion rejected two extremes:

- **One heavyweight doc-CRDT engine for everything** — wrong shape for
  low-frequency durable storage (history bloat, GC pressure) and for
  high-frequency game ops (snapshot cadence differs by orders of magnitude).
- **Per-consumer ad-hoc merge logic** — silent divergence bugs multiplied by
  number of consumers.

## Decision

### Sub-star boundary

The **convergence kernel** (`universal_storage_convergence`, pure Dart) is a
sub-star: it has its own center (the op/snapshot contract below) serving at
least two parents — Universal Storage's mesh provider and ecsly's world
sync. Neither parent may override kernel semantics:

- Parents choose *merge strategies* and *compaction policies* from what the
  kernel exposes; they never hand-roll their own ordering, version vectors,
  or fold rules.
- The kernel knows nothing about storage namespaces, worlds, actors, or
  transports. Messages in, messages out.
- Kernel changes require conformance evidence from **all** consuming parents
  (mesh provider suite + ecsly world suite), mirroring the ADR 0006 rule that
  backends prove themselves against one conformance suite.

### 1. Dual mode is mandatory: every replica keeps both an op log and snapshots

- Writes produce `OpRecord`s appended to a durable local log.
- Periodically (policy-driven), a replica folds its current state into a
  `Snapshot` and retires the covered ops.
- State is always reconstructible as `fold(snapshot ∪ ops_after_snapshot)`.
  This mirrors the harness invariant directly: derived state is a projection;
  compaction is a deliberate transform — never implicit, never lossy with
  respect to unacknowledged ops.

This is the same contract games use (checkpoint + command log). It is not a
coincidence and must not be re-derived per project again.

### 2. Core types (v1, pure Dart)

```
OpRecord      { op_id, doc_id, actor_id, hlc: HybridLogicalClock, payload }
VersionVector { actor_id -> max hlc.wall_clock seen }   // anti-entropy header
Snapshot      { doc_id, base_vv, bytes, created_at_hlc }
MergeStrategy // pluggable fold semantics per payload type
Compaction    // policy: when snapshot, which ops retire
```

- Ordering is **HLC-based** (hybrid logical clock): wall-clock anchored,
  causally consistent, monotonic per actor. Each device MUST persist its HLC
  counter across restarts; clock regression is absorbed, never trusted.
- v1 ships one strategy: **HLC-LWW register/map** — sufficient for settings,
  saves metadata, structured JSON namespaces.
- Sequence/text CRDT strategies (RGA/YATA family) are a later phase behind
  the same `MergeStrategy` seam; nothing above the seam changes when they
  arrive.
- Opaque binaries are out of kernel scope entirely — object-level LWW at the
  provider layer per [0010 §5](0010_mesh_sync_architecture.md).

### 3. Anti-entropy protocol (what travels on the wire)

Sync sessions exchange, per document:

1. Version vectors (cheap, constant-ish size).
2. Ops the remote is missing (delta stream), or a snapshot if the delta
   exceeds policy thresholds.
3. Acknowledgments recording causal delivery → feeds conservative op
   retirement (GC).

No tombstone-unbounded logs, no full-state gossip: VV diff decides, deltas or
snapshots carry.

## Non-claims

- **Not a database.** No queries, indexes, or subscriptions in v1; consumers
  hold state and apply folds.
- **Not yet real-time session infrastructure.** Presence/ephemeral state
  (cursor positions, live player transforms) can ride the same op path later
  but has no dedicated contract yet.
- **No formal proof.** Correctness claim rests on property tests (convergence:
  any replica order of the same op set yields identical state) in the kernel
  conformance suite — the weakest honest claim available without mechanization.

## Consequences

- ecsly gains multiplayer convergence without importing storage packages;
  mesh gains battle-tested merge without owning CRDT logic.
- The known-hard parts are now explicit obligations: HLC persistence across
  restarts, GC watermarks conservative until all-replica acks exist, and
  property-test coverage of commutativity/idempotence per shipped strategy.
- First consumer milestone: mesh provider passing headless conformance tests
  against a scripted fake transport, before any radio code exists.
