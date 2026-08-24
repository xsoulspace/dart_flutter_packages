import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// TCP-based [MeshTransport] for the pairing app example. This is the same
/// shape a full LAN transport uses: mDNS discovery would replace manual
/// host:port entry, and session encryption (pairing-derived AEAD keys)
/// wraps every frame.
final class TcpMeshTransport implements MeshTransport {
  TcpMeshTransport({required this.selfId, required this.bindPort});

  final String selfId;
  final int bindPort;

  ServerSocket? _server;
  final _incoming = StreamController<MeshSession>();

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  /// Starts listening so the peer can connect to us.
  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, bindPort);
    _server!.listen((socket) {
      _incoming.add(_SocketMeshSession(selfId, socket));
    });
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final hint = peer.endpointHints['tcp'];
    if (hint == null) {
      throw MeshConnectionException(peer.peerId, 'no tcp endpoint hint');
    }
    final parts = hint.split(':');
    final socket = await Socket.connect(
      parts[0],
      int.parse(parts[1]),
      timeout: const Duration(seconds: 3),
    );
    return _SocketMeshSession(peer.peerId, socket);
  }

  Future<void> dispose() async {
    await _incoming.close();
    await _server?.close();
  }
}

/// Frames raw socket bytes into messages using the shared codec.
final class _SocketMeshSession implements MeshSession {
  _SocketMeshSession(this.remotePeerId, this._socket) {
    _socket.listen(
      (final chunk) {
        for (final frame in _decoder.feed(chunk)) {
          _frames.add(frame);
        }
      },
      onDone: () => _frames.close(),
      onError: (final Object e) => _frames.addError(e),
    );
  }

  final FrameDecoder _decoder = FrameDecoder();

  @override
  final String remotePeerId;
  final Socket _socket;
  final _frames = StreamController<Uint8List>();
  var _closed = false;

  @override
  Stream<Uint8List> get inbound => _frames.stream;

  @override
  Future<void> send(final Uint8List payload) async {
    _socket.add(frameMessage(payload));
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Destroy the transport first, then wake pending inbound iterators.
    // Awaiting controller close before disconnect can stall while a peer's
    // exchange still owns a StreamIterator subscription.
    _socket.destroy();
    await _frames.close();
  }
}
