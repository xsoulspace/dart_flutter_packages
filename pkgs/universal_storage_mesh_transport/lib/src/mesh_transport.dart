import 'dart:async';
import 'dart:typed_data';

import 'mesh_peer.dart';

/// One encrypted link to a paired peer (ADR 0010 §1).
///
/// Implementations deliver framed, ordered messages. Confidentiality and
/// peer authentication are transport-level obligations: real transports
/// must establish session keys from pairing material before delivering any
/// inbound bytes; the fake transport used in tests is plaintext by design.
abstract interface class MeshSession {
  /// Stable id of the remote peer.
  String get remotePeerId;

  /// Inbound messages from the remote peer. Closes when the link drops.
  Stream<Uint8List> get inbound;

  Future<void> send(Uint8List payload);

  Future<void> close();
}

/// Radio/link abstraction inside the mesh family (ADR 0010 §1).
///
/// Implementations know nothing about documents or convergence: frames
/// carry convergence-kernel envelopes only. Concrete transports live in
/// separate packages (LAN first; BLE-class later as platform-channel
/// plugins).
abstract interface class MeshTransport {
  /// Sessions initiated by remote peers. Implementations must deliver every
  /// inbound session here exactly once.
  Stream<MeshSession> get incoming;

  /// Opens a session to a previously paired [peer].
  ///
  /// Throws [MeshConnectionException] when the peer is unreachable.
  Future<MeshSession> connect(MeshPeerRecord peer);
}
