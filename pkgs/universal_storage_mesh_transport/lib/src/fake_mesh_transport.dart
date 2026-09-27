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


/// Multi-peer in-memory transport for HOST-side tests: several controllers
/// dial one host and the test injects frames per session (born from the
/// vosges multi-sender arbiter tests).
///
/// ```dart
/// final hub = FakeMeshHub();
/// final phone = hub.openSession('phone');
/// final mac = hub.openSession('mac-controller');
/// hub.incoming.listen(hostAcceptsSession);
/// phone.receive(frame);
/// phone.sentStream.listen(assertHeartbeats);
/// ```
final class FakeMeshHub implements MeshTransport {
  final _incoming = StreamController<MeshSession>.broadcast();
  final _opened = <String, FakeHubSession>{};

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  List<MeshSession> get openSessions => List.unmodifiable(_opened.values);

  /// Opens (or re-opens) a session from [peerId]. A re-open closes the
  /// previous session for that peer, matching reconnect semantics.
  FakeHubSession openSession(final String peerId) {
    final previous = _opened.remove(peerId);
    previous?.closeLocally();
    final inbound = StreamController<Uint8List>();
    final session = FakeHubSession._(peerId, inbound);
    _opened[peerId] = session;
    _incoming.add(session);
    return session;
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    throw UnimplementedError('the hub is host-side only');
  }
}

final class FakeHubSession implements MeshSession {
  FakeHubSession._(this.remotePeerId, StreamController<Uint8List> inbound)
    : _inbound = inbound;

  @override
  final String remotePeerId;

  final StreamController<Uint8List> _inbound;
  final _sent = <Uint8List>[];
  var _closed = false;

  /// Frames the peer under test sent to this session.
  List<Uint8List> get sent => List.unmodifiable(_sent);

  /// Whether the peer under test closed this session.
  bool get closedByPeer => _closed;

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<void> send(final Uint8List payload) async {
    if (_closed) throw StateError('Session closed');
    _sent.add(payload);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inbound.close();
  }

  /// Simulates the peer's socket dying (done event on the inbound stream).
  void closeLocally() {
    if (_closed) return;
    _closed = true;
    unawaited(_inbound.close());
  }

  /// Injects a frame as if the peer sent it.
  void receive(final Uint8List bytes) => _inbound.add(bytes);
}
