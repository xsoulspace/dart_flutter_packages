/// High-level WebRTC for pure Dart, engine by the webrtc-rs sidecar.
///
/// Media-plane discipline (plagiarism ADR-032, encoded here): signaling
/// and control travel over [SignalingChannel]; frames travel over the
/// WebRTC data channel through [WebrtcDataChannelSink]. The two planes
/// never share a queue.
///
/// **Frame-flow contract** (proven by the loopback integration test):
/// the **offerer receives** frames and the **answerer sends** them.
/// A [WebrtcDataChannelSink] therefore binds to an *answerer* peer;
/// viewers build offerer peers via [SidecarPeerFactory.acceptPath].
/// v1 ships the data-channel transport (ICE/DTLS/SRTP-secured SCTP with
/// chunked frame envelopes — see `universal_webrtc_raw`'s sidecar
/// docs). Media tracks are the v2 roadmap behind the same interfaces.
library;

export 'src/frame_chunk_codec.dart';
export 'src/signaling_channel.dart';
export 'src/webrtc_frame_sink.dart';
export 'src/webrtc_peer_factory.dart';
