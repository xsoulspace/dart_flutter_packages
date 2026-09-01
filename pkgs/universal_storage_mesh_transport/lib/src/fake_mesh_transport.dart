import 'dart:async';
import 'dart:typed_data';

import 'mesh_peer.dart';
import 'mesh_transport.dart';

/// Deterministic in-memory transport for headless tests (ADR 0010
/// consequences: the provider is proven against this before any radio code
/// exists). Plaintext by design — session encryption belongs to real
/// transports.
///
/// ```dart
/// final pair = FakeMeshPair.paired(a: 'device-a', b: 'device-b');
/// final subscription = pair.a.incoming.listen(responder.handleSession);
/// final session = await pair.b.connect(peerRecordOfA);
/// ```
final class FakeMeshPair {
  FakeMeshPair._(this.a, this.b);

  factory FakeMeshPair.paired({
    final String a = 'device-a',
    final String b = 'device-b',
  }) {
    final transportA = FakeMeshTransport._(a);
    final transportB = FakeMeshTransport._(b);
    transportA._remote = transportB;
    transportB._remote = transportA;
    return FakeMeshPair._(transportA, transportB);
  }

  final FakeMeshTransport a;
  final FakeMeshTransport b;
}

final class FakeMeshTransport implements MeshTransport {
  FakeMeshTransport._(this.selfId);

  /// Peer id of the device owning this transport.
  final String selfId;

  /// Set to make the next [connect] throw, simulating an unreachable peer.
  bool failNextConnect = false;

  final _incoming = StreamController<MeshSession>();

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  FakeMeshTransport? _remote;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    if (failNextConnect) {
      failNextConnect = false;
      throw MeshConnectionException(peer.peerId, 'simulated partition');
    }
    final remote = _remote;
    if (remote == null || remote.selfId != peer.peerId) {
      // This transport cannot reach the requested peer; the provider
      // tries its other transports (a device may hold several links).
      throw MeshConnectionException(peer.peerId, 'not linked');
    }
    return _openSessionPair(remote);
  }

  FakeMeshSession _openSessionPair(final FakeMeshTransport remote) {
    // Single-subscription (not broadcast): events sent before the peer's
    // handler subscribes must be buffered, never dropped.
    final initiatorInbound = StreamController<Uint8List>();
    final responderInbound = StreamController<Uint8List>();
    final initiatorSession = FakeMeshSession(
      remotePeerId: remote.selfId,
      inbound: initiatorInbound.stream,
      onSend: responderInbound.add,
      onClose: () {},
    );
    final responderSession = FakeMeshSession(
      remotePeerId: selfId,
      inbound: responderInbound.stream,
      onSend: initiatorInbound.add,
      onClose: () {},
    );
    // Deliver the responder-side session asynchronously so the initiator's
    // connect() is not blocked on handler execution.
    scheduleMicrotask(() {
      remote._incoming.add(responderSession);
    });
    return initiatorSession;
  }
}

final class FakeMeshSession implements MeshSession {
  FakeMeshSession({
    required this.remotePeerId,
    required this._inbound,
    required this._onSend,
    required this._onClose,
  });

  @override
  final String remotePeerId;

  final Stream<Uint8List> _inbound;
  final void Function(Uint8List) _onSend;
  final void Function() _onClose;
  var _closed = false;

  @override
  Stream<Uint8List> get inbound => _inbound;

  @override
  Future<void> send(final Uint8List payload) async {
    if (_closed) throw StateError('Session closed');
    _onSend(payload);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClose();
  }
}
