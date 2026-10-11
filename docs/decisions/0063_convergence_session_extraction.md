# ADR 0063: The anti-entropy session core becomes `universal_storage_convergence_session`; mesh composes it, ecsly world sync is the second parent

**Status:** Accepted (2026-10-11)
**Builds on:** 0010 (mesh sync architecture), 0011 (convergence kernel dual
mode), 0047 (world layer), 0048 (interest-managed exchange)
**Related:** ecsly repo ADR 0004 (the bridge adopts this core)

## Context

The layering law across our repos is: universal_storage is the abstract
foundation; ecsly is the ECS framework with plugins that sits on top of it.
Both sides already share the merge substrate — the convergence kernel
(0011) — but the *session* layer around it had drifted into three
replica stacks:

1. universal_storage_mesh: wire codec (`MeshSyncProtocol`
   hello/sub/vv/delta) + the symmetric `_runExchange` round +
   `MeshSyncParticipant`;
2. ecsly's `ecsly_world_sync_bridge`: its own driver, message envelope,
   transport seam, and compaction policy (`WorldSyncDriver`,
   `WorldSyncMessage`, `WorldSyncTransport`, `SnapshotPolicy`) — a
   parallel implementation of the same exchange over a different wire;
3. last_answer's app-local `DocReplica` (headless_core) — forced
   app-side because no layer owned a replica with durable persistence
   and an HLC receive watermark.

The drift already produced a real bug, recorded in last_answer's
`mesh_task_board.dart`: `WorldSync` never ticks its HLC on receive, so a
local write issued after folding a remote op with an ahead wall clock
carries a LOWER HLC and loses LWW to a causally older write. last_answer
hand-patches the floor in the app ("the ecsly repo is not patched").
With more consumers arriving (one app, two games), every session-correctness
fix would otherwise have to land three times.

## Decision

**One session core, two parents: mesh composes it, ecsly adopts it.**

New package `universal_storage_convergence_session` (pure Dart; depends
only on the kernel + meta; knows nothing about transports or storage):

- **Wire codec** — `MeshSyncProtocol` moves here unchanged (same class
  names, byte-identical frames). mesh re-exports the symbols so consumer
  imports keep compiling. The 4-byte frame codec stays in
  `universal_storage_mesh_transport`.
- **`DeltaPlanner`** — the pure decision core of `_runExchange`: given a
  replica (vv, opsSince, needsSnapshotFor, snapshotFor) and a remote
  VersionVector (+ optional budget), decide ops-vs-snapshot. mesh calls
  it; ecsly will call it. Interest gating, priority, budgets, and
  presence stay mesh-side decorations.
- **`ReceiveWatermark`** — the generic HLC receive-watermark pattern
  extracted from last_answer's `DocReplica`: observe received op HLCs
  and snapshot `createdAt`, floor local ticks strictly above the
  watermark wall clock. This is the once-and-only fix for the
  ahead-clock LWW bug class.
- **`SnapshotPolicy`** — the generic compaction policy (size/age
  triggers, empty log never compacts), extracted from ecsly's bridge so
  both parents share the type; values stay parent-chosen.

The kernel is untouched — it remains the merge substrate only (0011).
Wire identity is proven by byte-level golden tests captured before the
refactor and required to pass unchanged after it. ecsly's adoption
(its ADR 0004) deletes the bridge's parallel driver/message/transport
stack.

## Consequences

- Anti-entropy protocol, delta planning, and watermark correctness now
  have exactly one home; mesh and ecsly parents (and any future
  consumer) inherit fixes together.
- mesh public API and wire bytes are unchanged; vosges and last_answer
  re-resolve without code changes.
- The session layer can iterate (protocol versions, planning policy)
  without dragging kernel version bumps for all five kernel consumers.
- last_answer's `DocReplica` keeps its document-specific lanes app-side;
  its generic core is now representable in the foundation and may shrink
  later (not migrated in this ADR).

## Non-claims

- No transport moves: `universal_storage_mesh_transport` is unchanged.
- No presence, pairing, blob-lane, interest, or budget moves: those stay
  mesh-side.
- No kernel changes and no kernel API additions.
- The kernel and this package are still not published to pub.dev; both
  ride the existing bootstrap path-resolution until publish (same clause
  as ecsly ADR 0001 §3).
