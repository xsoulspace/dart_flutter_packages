# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added
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
