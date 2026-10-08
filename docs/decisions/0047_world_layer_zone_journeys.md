# ADR 0047: The world layer — app- and game-agnostic zone journeys

- Status: Accepted
- Date: 2026-10-08
- North Star impact: `extends` — adds the L1/L2 world layer between the
  kernel and every consumer (mesh, apps, games, harness); no existing
  contract changes on the wire except the additive frames of
  [ADR 0048](0048_interest_managed_exchange.md).
- Builds on: [0010](0010_mesh_sync_architecture.md) (mesh),
  [0011](0011_convergence_kernel_dual_mode.md) (kernel),
  [0042](0042_content_addressed_chunk_store.md) (chunk store),
  [0031](0031_presence_link_topology_and_session_foundation.md) (presence)
- Related: ecsly `docs/decisions/0003` (game-side adapter),
  harness `docs/decisions/0083` (beat census contract),
  last_answer `docs/decisions/0014` (sectors-as-lenses)

## Context

Zone journeys — moving an actor, a surface, or a working set between
worlds/sectors with no loaders and no state loss — need mechanics game
engines solved over a decade: stable identity, interest management,
prefetch before the border, incremental catch-up, and eviction. Our
substrate is CRDT-based (no authority to migrate — every replica equal),
which deletes the hardest of those problems; the survey of the mesh stack
in October 2026 found the rest missing:

- anti-entropy covered EVERY doc of a store, always — sync cost scaled
  with the whole world, not the working set (fixed by
  [ADR 0048](0048_interest_managed_exchange.md));
- the sync brain (cycle, presence, scheduling) lived app-side in
  last_answer's `MeshStorageService` — every other consumer would have
  re-implemented it;
- addressing was bare docId everywhere; no naming layer, no census, no
  way to enumerate a zone before opening it;
- no prefetch/warm/evict anywhere; and blobs had no kernel path at all
  (chunk store since [ADR 0042](0042_content_addressed_chunk_store.md),
  not yet wired into this design).

Dependency verification settled the placement question empirically: the
game family (`ecsly_world_sync`) and the harness (`agentic_host`,
`agentic_harness`) already consume from `dart_flutter_packages`. The
storage family is the neutral ground — it must not learn Flutter, ecsly,
or the harness, and both of those must never learn radios.

## Decision

### 1. The layer model (what goes where)

```
L4 adapters (each repo owns its own)
   Flutter builders (apps) · game systems/policies (ecsly plugins)
   census schema + passport (harness)
L3 transports (exists): LAN WebSocket, addressed relay, session AEAD
L2 journey/session engine: interest-managed exchange, warm/evict
   working set, resume — universal_storage_mesh (MeshWorldSession)
L1 world model: Urn, MemberRef, InterestPolicy/Selection, ZoneCatalog,
   MemberCodec, JourneyPhase, Pulseable — NEW universal_storage_world
L0 kernel (exists): ConvergenceDoc, HLC, VersionVector, snapshots
```

Layer law: nothing in L0–L2 imports Flutter, ecsly, or the harness.
Domains above bring their own codecs and interest policies.

### 2. New package: `universal_storage_world` (pure Dart)

- `WorldUrn` — `world://<worldId>/<memberPath>`; the naming layer over
  bare docIds (the wire and store keys stay docIds; identity never
  changes when connectivity or zone changes).
- `InterestPolicy` / `InterestSelection` — see ADR 0048.
- `ZoneCatalog` / `ZoneCatalogCodec` — the zone census: an ordinary
  kernel-doc value (one LWW register) shipped by existing anti-entropy.
  The game "zone map" that makes prefetch possible: you cannot warm what
  you cannot enumerate.
- `MemberCodec` — THE app-agnostic seam: how one member kind (file, doc
  lane set, game entity, harness beat, blob manifest) maps content ↔
  kernel ops. `SingleFieldMemberCodec` reproduces the file semantics
  byte-for-byte; domains bring their own.
- `JourneyPhase` / `JourneyState` — the double-buffered border crossing
  as a pure state machine: `subscribing → warming → switching →
  catchingUp → settled`; the old zone stays live through warming; no
  phase is ever a loader. Orchestration is the host's; the machine
  validates the order.
- `Pulseable` — the ONLY scheduling contract (see §4).

### 3. The sync brain moves into the mesh package

`MeshWorldSession` (new, `universal_storage_mesh`): attached
`MeshSyncParticipant`s (the flush → exchange → absorb → compact seam),
presence over any `EphemeralFrameTransport` (moved verbatim from
last_answer), interest publication, and the pulse cycle.
`MeshStorageService` in last_answer is now a thin facade (relay hosting,
pairing with harness-world announcements, the app's three participant
adapters). `MemberCodec`/`UrnResolver` are provider-level seams with
defaults that preserve every existing wire/storage byte.

### 4. Scheduling law: hosts drive, the layer never owns a loop

`Pulseable.pulse()` is the whole contract — idempotent, coalescing,
never throwing into the host's loop. A game drops it into its existing
ecsly schedule (see ecsly ADR 0003); an app may use the
`startPeriodicPulse` convenience timer; the harness drives it from its
event loop. The oka/flutter pattern: capability objects pulled by the
host's own runner, like a Flutter `Ticker`.

### 5. Reusability statement

Chats, docs, coding surfaces, task boards, blobs, and game entities are
all just members: addressed by URNs, enumerated by catalogs, gated by
interest policies, carried by codecs. The journey machinery never learns
what any of them are.

## Property obligations

- Wire-format preservation: the default codec + additive sub frame keep
  pre-0048 replicas converging (tested against a scripted old-peer).
- Journey machine: illegal transitions throw; abort is always legal.
- Interest gate: out-of-selection members never cross the wire (mesh
  integration suite).

## One server, two planes (the second consumer)

Vosges (2026-10-08) became the stack's second consumer and paid for the
story this ADR promised but did not ship: a product whose ONE LAN server
already carries latency-critical realtime frames. The durable plane
joins without a second port, a pairing change, or a protocol change:

- `ClaimingMeshTransport` (universal_storage_mesh_transport) routes each
  inbound session to exactly one of two consumers by the CONTENT of its
  first frame — the sync protocol's `hello` arrives first by design, so
  the plane is self-declaring. Path or port splits cannot survive AEAD
  session wrappers (they expose only `MeshSession`); frame content does.
  The wrapper owns sealed sessions exclusively (they are
  single-subscription), forwards the deciding frame, parks silent
  sessions for a bounded claim timeout, and drops sessions that die
  before declaring.
- `Pulseable` proven in a second shape: both apps pull `pulse()` from
  loops they ALREADY run — the desktop's status watchdog (every 5th
  tick) and the controller's heartbeat watchdog (every 7th). No new
  timer anywhere; `startPeriodicPulse` stayed unused.
- The durable-side rule that deletions must survive an in-memory mesh
  working set lives in the CONSUMER (vosges's publish ledger in its own
  durable facade store) — the family stays free of per-app tombstone
  policy.

## Non-claims

- No spatial simulation and no coordinates in the storage family;
  spatial interest is a game-side `InterestPolicy` implementation.
- No beat-history sync (harness ADR 0083: the census, not the log).
- Sectors stay lenses (last_answer ADR 0014): borders govern
  visibility/attention, never permissions.
- Journey orchestration UI (warm/switch host code) is per-app; this ADR
  ships the machine and the session seam, not a widget.
