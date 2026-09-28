# universal_webrtc

High-level WebRTC for pure Dart: signaling contracts, a peer factory over
the webrtc-rs sidecar, and a `FrameSink` that pumps screencast frames
through the WebRTC data channel. Cross-platform wherever cargo runs;
WebRTC from day one with the media plane separated from signaling
(plagiarism ADR-032 discipline).

Part of the `universal_automation_*` family
([ADR 0037](../../docs/decisions/0037_universal_automation_family.md)).

## What it does

- `SignalingChannel` — the control plane: `SdpOffer`/`SdpAnswer`/
  `IceCandidate` envelopes over `LoopbackSignalingChannel` (same host,
  tests) or `WebSocketSignalingChannel` (production).
- `SidecarPeerFactory` — peer bring-up with the frame-flow contract:
  frames flow in both directions (offerer ↔ answerer), reassembled by the
  sidecar; bind the sink to whichever peer produces frames.
- `WebrtcDataChannelSink` — a screencast `FrameSink`; each `push`
  becomes a `send_frame` on the data channel.
- `FrameChunkCodec` / `FrameReassembler` — the 12-byte chunk envelope
  shared with the sidecar.

## Usage

```dart
final (viewerSignals, sourceSignals) = LoopbackSignalingChannel.pair();
final viewerFactory = SidecarPeerFactory(sidecar: viewerSidecar, signaling: viewerSignals);
final sourceFactory = SidecarPeerFactory(sidecar: sourceSidecar, signaling: sourceSignals);

final viewer = await viewerFactory.createPeer('pair-1', PeerRole.offerer);
final source = await sourceFactory.createPeer('pair-1', PeerRole.answerer);

final sink = WebrtcDataChannelSink(sidecar: sourceSidecar, peerId: 'pair-1');
await pipelineStart(sinks: [sink]); // feed from ScreencastPipeline
```

The repo's own test runs two real sidecar processes through this exact
path (`test/webrtc_test.dart`) — SDP, trickle ICE, DTLS/SCTP, and three
frames, end to end.

## Non-claims

- v1 is data-channel transport; media tracks (VP8/H264 via the same
  peer connections) are the v2 roadmap.
- No embedded browser engine: Web consumers get the WebRTC path via
  `dart:js_interop` later; the signaling envelope is already
  engine-agnostic.
- Only host candidates; TURN/STUN configuration is future work.
