# Changelog

## 0.1.1

- interface constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `SidecarPeerFactory.relayOnly` — `transportPolicy: relay` on the
  wire; gathering restricted to relayed candidates so connectivity is
  relay-mediated by construction (TURN proofs).
- feat: TURN relay proof (`test/turn_relay_test.dart`, env-gated
  `XS_TEST_TURN=1`): relay-only peers connect through a real coturn
  allocation, assert a `typ relay` candidate, and exchange frames both
  directions (multi-chunk included).
- feat: offerer→answerer (A→B) direction test; the historical
  "answerer sends only" restriction is retired — it was a
  send-before-open race, covered by `createPeer`'s `opened` handshake.
- docs: frame-flow contract corrected — frames flow in both directions.

- feat: TURN/STUN — `IceServerSpec` flows through `SidecarPeerFactory`
  to the sidecar's `RTCConfiguration`; cross-network pairing is now
  configurable per factory.

- feat: `SignalingChannel` contracts with loopback and WebSocket
  implementations.
- feat: `SidecarPeerFactory` with the offerer-receives / answerer-sends
  frame-flow contract.
- feat: `WebrtcDataChannelSink` implementing the screencast `FrameSink`
  interface.
- feat: `FrameChunkCodec` / `FrameReassembler` chunk envelope.
- feat: end-to-end loopback test over two real sidecar processes.
