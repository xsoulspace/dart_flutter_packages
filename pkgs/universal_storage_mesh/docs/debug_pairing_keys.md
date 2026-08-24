# Debugging log — pairing key mismatch (RESOLVED)

Historical record of the HKDF info-string bug in `PairingService`. Kept as
evidence of the debugging approach that worked (compare derived inputs on
both sides; prove the cause; then fix) after a long guess-and-check detour.

## Symptom

`pairing_service_test.dart` — "build → accept derives matching keys on both
sides" failed: Bob's `receiveKey` never equaled Alice's `sendKey` (and vice
versa), regardless of how the 64-byte HKDF output was split.

## Wrong approach (do not repeat)

Flipping `sendKey`/`receiveKey` half-assignments (`sublist(0,32)` vs
`sublist(32)`) back and forth across ~20 edit-run cycles. Swapping the same
two lines cannot fix a mismatch when the underlying 64 bytes differ between
sides. Lesson: if two runs produce different failures after an "equivalent"
change, stop and compare inputs, not outputs.

## Root cause

The responder path (`acceptQrPayload`) and initiator path
(`deriveInitiatorKeys`) fed **different HKDF `info` strings**:

- Bob (responder): `info = "$ourPeerId|$peerId"` = `"device-b|device-a"`
- Alice (initiator): `info = "$ourPeerId|$peerId"` = `"device-a|device-b"`

Different info → completely different derived key material per side. No
arrangement of output halves can match because the input derivation differs.

## Fix

Canonicalize the info string so both sides compute the identical value —
sort the peer ids lexicographically:

```dart
static List<int> _kdfInfo(final String a, final String b) {
  final ids = [a, b]..sort();
  return utf8.encode('$_protocolName|${ids[0]}|${ids[1]}');
}
```

Both methods now call `_kdfInfo(ourPeerId, peerId)`. Directional keys are
assigned as mirrored halves:

- Responder (`acceptQrPayload`): send = first half, receive = second half
- Initiator (`deriveInitiatorKeys`): send = second half, receive = first half

## Verification

All four pairing tests pass:

1. build → accept derives matching directional keys on both sides
2. tampered payload rejected (byte flip inside signed body)
3. wrong identity key rejected (Mallory substitution)
4. malformed payload (bad prefix) rejected

Full suite at time of fix: 47/47 green across mesh, transport, convergence,
interface packages.

## Crypto primitives validated

`tool/crypto_probe.dart` confirmed on this machine: Ed25519 sign/verify,
X25519 shared-secret symmetry (32 bytes both sides), HKDF-SHA256 derive,
AES-GCM round-trip via package `cryptography` 2.x.
