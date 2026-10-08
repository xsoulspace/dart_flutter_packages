# ADR 0050: The realtime event plane, out of the box

**Status:** Accepted (2026-10-08)
**Consumes:** 0010 (mesh transports/sessions), 0047 (plane claiming).
**Reference consumer shape:** vosges's gesture stream
(`gesture-input/v1`), whose working realtime code this distills — the
library is what remains when the app-specific policy is taken out.

## Context

Every app on the mesh family re-implements the same four realtime
semantics on top of a raw `MeshSession`: liveness (heartbeats, staleness,
release-on-loss), droppable newest-wins streams (pointer/cursor frames —
a slow link must bound lag at one frame, never queue seconds of stale
pointers), reliable exactly-once events (pinch edges, keys), and
multi-sender authority (who drives, when a handoff releases held input).
vosges proved the shape; the world layer proved the plane-splitting; the
libraries still made every app write the session plumbing itself.

## Decision

`universal_storage_realtime` — three types and a policy seam:

- **`RealtimeEnvelope`** — the wire frame: `{rt: 1, type, seq, rel, ts,
  payload}`. The envelope defines DELIVERY, never schema; the payload is
  an app-owned map. `looksLikeRealtimeFrame` classifies the plane's
  first frame, so realtime is a fourth claimable plane next to sync and
  blobs (ADR 0047).
- **`RealtimeLink`** — one session upgraded with: bidirectional
  heartbeats + staleness (armed from birth — a peer that never speaks
  goes stale too); `sendDroppable` (newest-wins PER TYPE — the in-flight
  frame goes first, newer calls replace the pending one, callers never
  block); `sendReliable` (monotonic sequence, replay-deduped on
  receipt); reserved control (`heartbeat`, `release-all`) handled
  internally, never surfaced, never authoritative.
- **`RealtimeHost`** — adopts every session from a claimed plane, keeps
  exactly one authoritative sender, surfaces EVERY app event with an
  authority flag (richer policies consume non-authoritative streams
  directly instead of re-implementing plumbing), and encodes the release
  safety law: release-alls, session loss, and staleness fire
  `onReleaseAll` BEFORE the claim clears.
- **`RealtimeArbiter`** — the policy seam. The default
  `FirstClaimArbiter` is the gesture-keyboard semantics (first claimant
  wins, idle handoff). vosges's per-frame pointer fusion is a policy
  implementation + non-authoritative event consumption, not a fork.

**What an app brings:** its event schema (payloads), its arbiter (only
if it wants more than first-claim), and its transport (the same sealed
LAN link the sync/blob planes ride). Nothing else.

## Property obligations

- Reserved control frames never reach `onEvent` and never claim
  authority (tested).
- Reliable dedupe: a replayed sequence never re-delivers (tested).
- Droppable coalescing: at most one frame in flight per type; the
  pending slot holds only the newest (tested, deterministically, behind
  gated sends).
- Release safety: `onReleaseAll` fires before the claim clears on all
  three paths — release-all, session loss, staleness (tested).
- Staleness is armed from birth (a silent peer dies stale, not never).

## Adoption (2026-10-08, amended)

vosges IS migrated (the first consumer, same day as the ADR): the
`gesture_mesh` client/host are now adapters over RealtimeLink/
RealtimeHost — the gesture vocabulary, fusion policy, and connection
state machine stayed; the four semantics became the library's. The
migration forced five generalizations, all backported:

- **tickDriven** (links + host): vosges's watchdogs pulse `tick()` and
  its tests inject a clock — internal timers would race both. The
  default stays timer-mode (LA uses it).
- **adoptSession** (the auth seam): the host decides who may drive even
  when the transport cannot prove it (LA's relay registrations).
- **claimSender + onAdopted**: the reconnect law — a re-adopting sender
  reclaims without waiting to speak, so a bystander's stray event in the
  reconnect window cannot steal authority.
- **isClaimable**: an announce/hello surfaced for classification must
  not move authority (vosges's `session_start`).
- **sendTo**: the host-to-sender app direction (the LA live plane's
  rebroadcast rides it).

The eager `session_start` announce (client, on attach) is also a
claim-chain requirement: a claiming transport classifies a session by
its FIRST frame, so a silent client would park its session for the
claim timeout before the host ever sees it. Announce on connect = plane
classification within one round trip.

LA adopts the plane as the **live multiplayer layer** (`live_mesh_service.dart`):
a dedicated `<peerId>-rt` registration on the SAME relay (the relay keys
clients by declared id), owner aggregates + rebroadcasts `live-state`
(droppable newest-wins makes the rebroadcast self-throttling), the
privacy gate sits AT THE SOURCE (human activity is opt-in per device;
agents always publish), and `setSharing(false)` RETRACTS via a reliable
`live-retract` frame. The adoption gate holds the paired-peer list.
The HUMAN side is wired (2026-10-08): a settings-panel toggle flips the
gate, and `HumanLivePresence` publishes watching/typing/caret from the
chat surface's own hooks (throttled; gated at the source — the hooks
fire unconditionally and nothing leaves while sharing is off).

## Non-claims

- No latency guarantees beyond the transport's; no QoS scheduling; no
  fragmentation (payloads are maps — big binaries belong to the blob
  lane, ADR 0049).
- No reconnection policy — links die loudly; reconnection is the app's
  composition (vosges's autoconnect watchdog remains the pattern).
- Live-plane frames are not signed (LA): the adopt gate is the door;
  an AEAD upgrade would follow the vosges SessionAeadTransport pattern.
