# ADR 0010: Mesh sync architecture — serverless peers, QR pairing, transport seam

- Status: Accepted
- Date: 2026-08-24
- North Star impact: `applies`
- Builds on: [0006](0006_universal_storage_production_hardening.md) (kernel split, capability model), [0007](0007_extensibility_seams_and_conformance.md) (seams policy)
- Related: [0011](0011_convergence_kernel_dual_mode.md) (merge semantics), [0001](0001_native_ffi_bridge_acp.md)

## Context

Every Universal Storage sync target today is cloud-arbitrated (GitHub API,
CloudKit): availability depends on a service, and the service resolves
conflicts. Two growing consumers need device-to-device replication without any
origin:

- **Note-taking / personal data apps** built on ecsly: two phones, one user,
  no account required, sync when devices meet.
- **Ecsly worlds across devices**: continue a game/session from phone to web,
  let a friend join mid-session.

Requirements gathered:

1. Devices discover and connect over whatever link exists (LAN Wi-Fi first;
   Bluetooth / OS P2P frameworks later).
2. Initial trust established by scanning the other device's QR code.
3. Links are intermittent. Sync must happen whenever a link exists, or on
   explicit user action — never block reads/writes on connectivity.
4. Strictly serverless. If a relay or bridge is ever needed, it must be added
   **as a node**, not as an origin (see §2).

Two implementation policies were considered and decided here:

- **Rust bindings for transports/convergence**: rejected. Radios (BLE,
  MultipeerConnectivity, Nearby Connections) are OS APIs reachable only through
  platform channels regardless; no proven Rust library wraps them better than
  existing Dart plugins. Crypto and CRDT have viable pure-Dart foundations
  (`cryptography`, hand-rolled HLC/LWW — see [0011](0011_convergence_kernel_dual_mode.md)).
  Per-platform native build matrices were judged not worth the maintenance
  burden. Pure Dart everywhere.
- **Serverless with central fallback**: rejected as a *mode*. See §2.

## Decision

### 1. Mesh is a provider family, entering through the existing seam

New packages, zero changes to `universal_storage_sync` internals:

| Package | Responsibility |
| --- | --- |
| `universal_storage_mesh` | `MeshStorageConfig` + `StorageProvider`; pairing records; sync sessions |
| `universal_storage_mesh_transport` | `MeshTransport` interface + LAN (mDNS + TCP) implementation |
| `universal_storage_mesh_ble` (later) | BLE / MultipeerConnectivity / Nearby transports, platform-channel plugins |

This is extension seam #5 from ADR 0007 (`StorageProviderRegistry.register`),
plus one new narrow seam *inside the mesh family only*: `MeshTransport`.

```dart
abstract interface class MeshTransport {
  /// Advertisements from reachable, previously paired peers.
  Stream<MeshPeerDiscovery> get discoveries;

  /// Opens an encrypted session to a paired peer.
  Future<MeshSession> connect(MeshPeerRecord peer);
}

abstract interface class MeshSession {
  Stream<Uint8List> get inbound;
  Future<void> send(Uint8List payload); // framed convergence messages (0011)
  Future<void> close();
}
```

The provider knows nothing about radios; transports know nothing about
documents. Frames carry convergence-kernel messages only.

### 2. Uniform node model — relay is a node, never an origin

Every participant runs the same protocol and holds the same standing: a full
replica with its own local store. There is no origin, coordinator, or
authoritative copy anywhere in the design.

If topology demands it later, special participants join **as nodes with a
role**, not as a tier:

- **Relay node**: forwards ciphertext between peers it has paired with. Sees
  no plaintext (sessions are end-to-end encrypted between the endpoints).
- **Bridge node**: a paired node that also speaks a cloud protocol
  (e.g. also configured with git_offline), giving asynchronous reach across
  networks. From the mesh's perspective it is just another peer whose
  availability window differs.

Consequence: no component may ever gain "resolve conflict" authority by being
a relay or bridge. Convergence is decided exclusively by the kernel
([0011](0011_convergence_kernel_dual_mode.md)) at every replica identically.

### 3. Pairing = out-of-band trust bootstrap; reconnection is automatic

QR contents (signed by the advertiser's long-lived Ed25519 identity key):

```
mesh-pair/v1
  peer_id        stable random id
  identity_key   Ed25519 public key
  transport_hint scheme + endpoint hints (e.g. mdns service name)
```

Scanning verifies the signature and completes a key exchange (X25519 → HKDF →
session AEAD keys) over the discovered transport; the QR scan itself is the
authenticator — no password, no PKI. Result is a persisted `MeshPeerRecord`
(peer id, identity key, shared secrets metadata). Subsequent connections skip
pairing entirely; re-pairing happens only on key rotation or explicit revoke.

All primitives come from the pure-Dart `cryptography` package. No custom
crypto is invented; if a construction is not expressible with those building
blocks, the design is wrong.

### 4. Sync model: opportunistic sessions over the existing outbox

- Reads/writes never touch the network. Local store is always authoritative
  for latency; convergence catches up (same posture as offline-git today).
- On link establishment (or manual trigger): open `MeshSession`, exchange
  version vectors + ops/snapshots per [0011](0011_convergence_kernel_dual_mode.md),
  drain both directions, close.
- Existing machinery is reused as-is: `SyncOutboxEntry` queues,
  `SyncQueuePolicy` backoff, `ConflictResolutionStrategy` staging for
  policy-level conflicts that survive CRDT merge (e.g. binary LWW losers).
- `StorageCapabilities.syncAvailability` for mesh = `withRemoteConfig`
  semantics (sync works iff ≥1 peer link exists), documented so profile
  negotiation behaves correctly.

### 5. Merge policy is per-namespace, declared in the profile

Not everything is CRDT-mergeable. `StorageNamespaceProfile.requiredCapabilities`
gains a merge-policy declaration consumed by the provider:

| Content | Policy |
| --- | --- |
| Structured JSON (settings, saves metadata) | Kernel merge: HLC-LWW registers/maps ([0011](0011_convergence_kernel_dual_mode.md)) |
| Rich text / documents | Kernel merge: sequence CRDT (later phase) |
| Opaque binaries (images, blobs) | No CRDT. Object-level LWW at provider layer; loser staged via existing conflict workflow |

## Non-claims

- **No liveness guarantee.** Two devices that are never co-present (directly
  or via a paired relay/bridge node) stay diverged until a path exists. This
  is accepted as the definition of serverless.
- **Web/desktop**: LAN transport works wherever sockets + mDNS discovery work;
  BLE-class transports are mobile-only initially.
- **No anonymity.** Peers know each other's stable identity keys by design.
- Mesh does not replace cloud providers; a bridge node composes them.

## Consequences

- Two new packages now, third deferred until a BLE-class transport is actually
  needed by product code (no speculative radio work).
- `MeshTransport` will be proven against a scripted fake transport before any
  real radio implementation exists — conformance tests run headless.
- Relay/bridge roles are deliberately *undesigned* beyond §2's constraint.
  Building them before a second real deployment exists would be mechanism
  becoming mission.
