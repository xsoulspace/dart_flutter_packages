# 39. Mesh session AEAD channel crypto

Date: 2026-09-27

## Status

Accepted

## Context

ADR 0010 §1 makes confidentiality and peer authentication
transport-level obligations: "real transports must establish session
keys from pairing material before delivering any inbound bytes". No
transport fulfilled this. The stopgap (ADR 0031 §3) signs each
ephemeral frame with the sender's Ed25519 identity key — which
measured 387–453 ms per sign on an Android debug device (vosges
`docs/validation.md`): per-frame signing starves landmark delivery and
provides no confidentiality at all.

## Decision

`pkgs/universal_storage_session_aead` implements the end-state channel,
protocol `mesh-session/v1`:

1. **One handshake per session, Noise-XX-shaped.** M1 (initiator hello:
   fresh X25519 ephemeral + peer id + identity-key ride-along), M2
   (responder hello body with the Ed25519 transcript signature APPENDED
   as trailing 64 raw bytes — the `mesh-pair/v1` layout, so the
   transcript stays byte-exact on both sides), M3 (initiator transcript
   signature). Both signatures commit to both bodies with role labels,
   length prefixes, and the protocol-name prefix.
2. **Key schedule.** HKDF-SHA256 over the X25519 ephemeral ECDH; salt =
   protocol name, info = sorted peer ids ‖ SHA-256(full transcript) —
   the PairingService convention extended with channel binding. The
   64-byte okm splits directionally exactly like pairing (responder
   sends with the first half).
3. **Per-frame AEAD instead of per-frame signatures.** ChaCha20-Poly1305
   with a binary record `version ‖ sequence(u64 LE) ‖ ct ‖ tag`; the
   header is AAD, the nonce is `0x00000000 ‖ sequence`. Synchronous
   pure-Dart seal/open; replays and late records drop as named data.
4. **Trust model = ADR 0031 §3.** Pre-shared pins take precedence;
   optional TOFU binds a verified key on first contact; strict mode
   rejects unknown peers before the responder reveals anything.
5. **Seam.** `SessionAeadTransport` wraps any `MeshTransport`
   (`connect` initiates, `incoming` accepts in parallel); raw
   `SessionAeadSession.start/accept` drive the handshake over any
   `MeshSession`. Handshake failures close the raw session, surface via
   `onHandshakeFailure`, and never kill the streams.

## Consequences

- Measured on Apple Silicon VM: seal 48 B ≈ 60 µs, open ≈ 23 µs, full
  handshake ≈ 44 ms, vs 8 ms for ONE Ed25519 sign — the per-frame path
  is ~100× cheaper than per-frame signing (several orders of magnitude
  more on Android debug, where a sign measured 387–453 ms).
- Confidentiality, integrity, and replay protection that the signed
  frame scheme never had.
- Forward secrecy: fresh ephemerals per session; a compromised identity
  key cannot decrypt past sessions.
- Ordered transports only: late records are dropped, not buffered.
  No rekey — reconnect instead (new handshake, new keys).
- Consumers (vosges gesture mesh) can now replace per-frame signing
  with the wrapped transport entirely; the isolate signing machinery
  remains for callers that must stay on the frame-auth seam.

## References

- ADR 0010 (mesh sync architecture), ADR 0031 (presence link topology,
  frame authentication)
- `universal_storage_session_aead/README.md` (protocol tables, numbers)
- vosges `docs/realtime-plan.md` §3 (the plan this implements)
