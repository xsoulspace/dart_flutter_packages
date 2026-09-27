# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added
- feat: `create_peer` accepts `iceServers` (STUN/TURN with optional
  credentials) mapped onto webrtc-rs `RTCIceServer`s.

- feat: webrtc-rs sidecar (`xs-webrtc-sidecar/1`): peer lifecycle, SDP
  offer/answer both directions, trickle ICE, chunked data-channel
  frames with reassembly.
- feat: `SidecarTransport` seam (`ProcessSidecarTransport` + fakes) and
  `SidecarClient` with handshake validation, correlated requests, and a
  broadcast event stream.
