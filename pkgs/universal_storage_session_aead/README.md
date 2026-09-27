# universal_storage_session_aead

Session encryption for Universal Storage mesh links (ADR 0039): a
Noise-shaped, mutually-authenticated handshake over the existing pairing
identity keys derives ChaCha20-Poly1305 session keys, and every frame on
the wire is sealed — confidentiality, integrity, and replay protection
once per session instead of a signature per frame.

ADR 0010 §1 makes confidentiality and peer authentication
transport-level obligations of real transports. This package discharges
that obligation for ANY `MeshTransport` (LAN socket, relay, fake):

```dart
final transport = SessionAeadTransport(
  inner: myWebSocketTransport,
  identityKeyPair: myIdentity,          // Ed25519, from PairingService
  selfId: 'device-a',
  pinnedIdentityKeys: {'device-b': bIdentityKeyBytes},
  onHandshakeFailure: (raw, error, stackTrace) => log(error),
);
final session = await transport.connect(peerRecordOfB); // sealed
final acceptedSessions = transport.incoming;            // sealed

await session.send(frame);              // ChaCha20-Poly1305 sealed
session.inbound.listen(handlePlaintext);
```

## Protocol: `mesh-session/v1`

Three handshake messages, then sealed data:

| # | Direction | Content |
| --- | --- | --- |
| M1 | initiator → responder | JSON hello: fresh X25519 ephemeral, peer id, Ed25519 identity key (TOFU ride-along) |
| M2 | responder → initiator | hello body ‖ Ed25519 signature over the responder transcript (the `mesh-pair/v1` append layout) |
| M3 | initiator → responder | JSON confirm: Ed25519 signature over the initiator transcript |

Both signatures commit to the full transcript (both bodies, role-labeled,
length-prefixed, protocol-prefixed). Session keys are
`HKDF-SHA256(X25519 ephemerals, salt = protocol name, info = sorted peer
ids ‖ SHA-256(transcript))`, split directionally exactly like
`PairingService`. Fresh ephemerals per handshake give forward secrecy.

Data records are binary: `version(1) ‖ sequence(u64 LE) ‖
ciphertext ‖ Poly1305 tag(16)`. The header is AAD; the nonce is
`0x00000000 ‖ sequence`, unique per direction under per-session keys.
Replays and late records drop as named data (`open` returns `null`,
`droppedInboundCount` counts).

Trust model mirrors `MeshFrameAuthenticator` (ADR 0031 §3): pre-shared
pins always take precedence; `trustOnFirstUse` binds a verified key on
first contact only. Strict mode rejects unknown peers BEFORE the
responder reveals anything (no signed reply leaves the host).

## Measured cost (Apple Silicon, Dart VM — `dart run tool/benchmark.dart`)

| Operation | Cost |
| --- | --- |
| seal 48 B | ~60 µs |
| open 48 B | ~23 µs |
| seal / open 1 KiB | ~120 / 105 µs |
| full handshake (2× Ed25519 sign + verify, X25519, HKDF) | ~44 ms |
| Ed25519 sign alone (what per-frame signing costs) | ~8 ms |

The per-frame path is ~100× cheaper than one Ed25519 signature on the
VM; on an Android debug build the same signature measured 387–453 ms
(vosges `docs/validation.md`), making the session channel several orders
of magnitude cheaper per frame there. The handshake is paid once per
session and costs the same as TWO signed frames in the old scheme.
Both seal and open are synchronous pure Dart — no microtask hops at
30 Hz on a UI isolate.

## Scope and non-goals

- Ordered transports only (the `MeshSession` seam guarantees ordering);
  a late record is dropped by design rather than buffered.
- No rekey: session keys live for the session; reconnect = new
  handshake = new keys. Long-lived links that need rekeying should
  reconnect on a schedule.
- The initiator's first message is unauthenticated (as in Noise_XX):
  the responder learns and verifies the initiator's identity from M3
  before any key is accepted, and strict responders reject unknown
  peers before revealing their own signed reply.

Run tests with `dart test`, the benchmark with
`dart run tool/benchmark.dart`.
