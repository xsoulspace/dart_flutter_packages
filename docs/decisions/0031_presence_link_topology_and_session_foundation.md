# ADR 0031: Presence link topology and the transport-agnostic presence foundation

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `clarifies` (resolves the open plumbing question left
  by [0029](0029_convergence_kernel_presence_and_sequence_strategy.md) §1
  and the mesh ADR [0010](0010_mesh_sync_architecture.md); no boundary change)
- Builds on: 0010, 0029
- Driving consumers: last_answer (doc sessions, remote permission routing);
  ecsly (world sessions); any app/game needing live presence

## Context

ADR 0029 landed dual-mode presence (transport-level ephemeral frames +
kernel-queryable ephemeral registry) and left the plumbing question open:
which connection carries the frames in the real product? The candidates
were: (A) app-layer-owned separate link, (B) side-channel interleaved into
`MeshStorageProvider`'s anti-entropy exchange, (C) shared connection,
separate logical channels.

## Decision

### 1. Topology: shared connection, doc-scoped channels, app-owned session (C)

- ONE connection to the relay per peer; durable anti-entropy and ephemeral
  presence are two logical channels over it. The transport already
  supports this (`AddressedRelayClient.sendEphemeral` rides the same
  client as data frames).
- Presence is **doc-scoped** ("this document is open here"), never
  store-scoped ("this store syncs"). The deciding criterion: sync
  availability ≠ presence; a background sync must not make a device
  visible as present in a document it never opened. This kills option B
  (provider exchange stays a pure hello/vv/delta state machine — never
  versioned for presence) and selects C with app-layer session ownership.
- Presence lifetime = doc session: `join` on doc open, `leave` on close,
  ping on activity, ttl as the crash backstop.

### 2. Foundation lives in the mesh package — reusable beyond last_answer

`universal_storage_mesh` grows a **transport-agnostic presence session**,
so ecsly worlds, games, and other apps reuse it instead of re-deriving:

- a minimal `EphemeralFrameTransport` interface (send / receive /
  connection-state) — the mesh relay transport is one implementation;
  other transports (sockets, radios, in-proc fakes) plug in without
  touching the session;
- `MeshPresenceSession` owns the link lifecycle (join/leave/ping/sweep)
  over that interface and feeds `MeshPresenceTracker` (already landed,
  already doc-keyed and peer-keyed — it stays the kernel fold);
- nothing in the foundation knows about documents, worlds, or last_answer.

### 3. Frame authentication binds frames to PEER identity

The threat: a frame claiming `fromPeerId: X` sent by a peer that is not X.
Fix at the transport layer, using the identity keypairs pairing already
issues: ephemeral frames are SIGNED (payload + fromPeerId + timestamp)
and receivers verify against the registered peer identity key BEFORE
feeding the tracker. The tracker's forged-actor guard stays as
defense-in-depth, not the primary check. Unauthenticated frames are
dropped as named data, never folded.

### 4. Actor identity is a layer ABOVE peer identity (see last_answer ADR 0007)

Frames authenticate the PEER (device). Actors — a model with a role, an
agent, a human — ride the frame PAYLOAD as announcements keyed
`(peerId, actorId)`. Rosters sync as durable kernel ops so an actor
profile follows its user's devices. An actor announcement never grants
authority: agency still flows through the permission round-trip
(deny-by-default per device). Product surface (roster panel, actor
labels) is specified in last_answer ADR 0007.

### 5. Adaptive cadence is policy-with-bounds, not free knobs

`PresenceConfig` with named presets and invariants:

- `ttl = ttlFactor × pingInterval` (default factor 3 — a peer expires
  after ~3 missed pings);
- presets: `interactive` (short ping/ttl — games, live co-editing),
  `background` (longer — document viewing), chosen by the embedding app;
- cadence may adapt to activity (fast actions → shorter interval within
  preset bounds), never beyond the preset's bounds;
- constructor-level for apps/games; user-facing settings are a later,
  separate product decision.

### 6. Wire fix now: `details` namespace

Presence register values move consumer payloads into a nested `details`
map immediately (chosen over a reserved-key convention on quality +
maintenance grounds: no key-coupling between tracker and consumers;
performance impact is one map level). This is a wire change taken BEFORE
any product depends on the flat shape — cheapest moment it will ever be.

## Non-claims

- No radio/BLE transports, no relay-side TTL enforcement (kernel HLC wall
  clock remains the expiry anchor), no presence-based authorization
  (presence is observation, never permission).

## Consequences

- `_runExchange` never changes for presence — the anti-entropy protocol
  stays stable and testable.
- ecsly/games get multiplayer presence by implementing (or reusing) one
  transport interface; the kernel fold they already share does the rest.
- The mesh package gains signing + verification obligations on the
  ephemeral path (identity keys are already materialized by pairing).
