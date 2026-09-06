import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Lifecycle state of a transport's link to its peers.
enum EphemeralLinkState {
  /// No usable link; sends may fail and inbound frames stop.
  disconnected,

  /// The link is up; frames flow both ways.
  connected,
}

/// Transport-agnostic seam for ephemeral frames (ADR 0031 §2): send /
/// receive / connection-state. The addressed relay is one implementation
/// ([AddressedRelayEphemeralTransport]); sockets, radios and in-proc
/// fakes plug in without touching [MeshPresenceSession].
///
/// Implementations know nothing about documents, worlds, or the fold:
/// frames are opaque [MeshEphemeralFrame]s on a shared connection, and
/// presence is just one logical channel over them (ADR 0031 §1).
abstract interface class EphemeralFrameTransport {
  /// Frames received from peers. Bytes that do not decode as a frame of
  /// the current codec version are skipped by the implementation —
  /// consumers only ever see decodable frames and decide themselves
  /// what is authentic (ADR 0031 §3).
  ///
  /// Buffered until listened: frames sent before a consumer subscribes
  /// are delivered, never dropped.
  Stream<MeshEphemeralFrame> get frames;

  /// Publishes [frame] to every reachable peer (presence is a channel
  /// broadcast, never a directed message).
  Future<void> send(MeshEphemeralFrame frame);

  /// Current link state.
  EphemeralLinkState get connectionState;

  /// Emits on every [connectionState] change.
  Stream<EphemeralLinkState> get connectionChanges;
}
