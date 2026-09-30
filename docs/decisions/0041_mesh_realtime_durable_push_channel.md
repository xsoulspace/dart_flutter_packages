# ADR 0041: Mesh realtime durable push channel (live mode + change notifications)

- Status: Accepted
- Date: 2026-09-29
- North Star impact: `clarifies` (resolves the batch-only sync posture left
  implicit in [0010 §4](0010_mesh_sync_architecture.md); the link topology,
  channel split, and crypto of [0031](0031_presence_link_topology_and_session_foundation.md)
  and [0039](0039_mesh_session_aead_channel_crypto.md) are unchanged)
- Builds on: 0010, 0011, 0031, 0039
- Driving consumers: last_answer (human/agent doc co-edit), ecsly (world
  sync), vosges (paired-peer records) — all three ride the same mesh stack,
  so one implementation serves all of them.

## Context

Durable replication today is batch-only: local writes never touch the
network, and remote ops arrive only inside opportunistic single-round
exchanges (`MeshSyncProtocol` hello/vv/delta, then close). The convergence
kernel already applies each op synchronously in well under a millisecond,
presence already proves the persistent-channel pattern (`AddressedRelayClient`
holds one socket with many logical channels; `SessionAeadTransport` seals
frames at ~60 µs), and there is no change-notification surface anywhere, so
even locally applied remote ops cannot wake UIs or agents without polling.

The gap is therefore provider lifecycle and notification, not a subsystem.

## Decision

### 1. A third logical channel on the same connection: durable op push

The 0031 topology (ONE connection per peer; logical channels over it) gains a
durable channel beside the anti-entropy and ephemeral-presence channels.

- `MeshStorageProvider` grows a live-session mode: sessions may be held open
  instead of closed after one exchange.
- Each op returned by `applyLocal` is forwarded to connected peers as it is
  issued; inbound ops apply incrementally through the existing `applyRemote`
  dedupe path. No new merge semantics, no new ordering, no new versioning.
- Disconnects degrade silently to the existing opportunistic `sync()`.

### 2. Push is acceleration; anti-entropy remains the correctness authority

`sync()` / `_runExchange` are unchanged as the background repair path. A
missed or dropped push is repaired by the next version-vector reconciliation.
No acknowledgment, retry, or delivery guarantee is introduced at the push
layer — that would duplicate what VV anti-entropy already proves.

### 3. Change notification is a local facts stream

The provider (and `ConvergenceDoc`) expose a stream of applied-change events
(op applied, state delta) so UIs and agents subscribe instead of polling.
Notifications report facts already applied locally and grant no authority —
they are observation, like presence ([0031](0031_presence_link_topology_and_session_foundation.md)).

### 4. Scoping

Durable push is store-scoped like anti-entropy (a background sync must not
require opening documents); presence stays doc-scoped per 0031. Frames ride
`SessionAeadTransport`; the relay stays ciphertext-blind (0039).

## Property obligations

- Two-replica property test: any interleaving of live-mode delivery converges
  to the identical state batch mode produces (per ADR 0011 obligations).
- Latency gate: op echo p50 over a LAN relay ≤ 50 ms; relay-path numbers
  recorded in the package README (not a release gate until a second consumer
  ships).
- No new strategy, compaction, or ephemeral semantics — the kernel is
  untouched.

## Non-claims

- No delivery guarantee from push alone; correctness rests on anti-entropy.
- No live queries or server-side subscriptions; watch streams are local
  change events.
- No WebRTC transport; the vosges finding stands (relay + AEAD beats
  TURN-class paths for cross-network latency).
- No radio/BLE work; transports are unchanged.

## Consequences

- `universal_storage_mesh` grows a session-lifecycle layer (hold open, push,
  incremental inbound apply, watch streams); kernel, transports, and crypto
  are unchanged.
- last_answer, ecsly, and vosges inherit interactive-latency replication by
  upgrading the provider — no per-product sync code.
- Agents streaming text into docs (ADR 0029 sequence strategy) become
  interactive: token-level ops push as issued.
