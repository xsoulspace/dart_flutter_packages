import 'dart:async';
import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client session for the example relay.
final class WebSocketMeshSession implements MeshSession {
  WebSocketMeshSession({required this.remotePeerId, required WebSocketChannel channel})
    : _channel = channel;

  @override
  final String remotePeerId;
  final WebSocketChannel _channel;

  @override
  Stream<Uint8List> get inbound =>
      _channel.stream.cast<List<int>>().map(Uint8List.fromList);

  @override
  Future<void> send(final Uint8List payload) async =>
      _channel.sink.add(payload);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

/// WebSocket [MeshTransport] for a shared example relay.
final class WebSocketMeshTransport implements MeshTransport {
  WebSocketMeshTransport({
    required this.selfId,
    required this.endpoint,
  });

  final String selfId;
  final Uri endpoint;
  final _incoming = StreamController<MeshSession>();

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  /// Starts listening for peers that connect to this app-hosted relay.
  Future<void> start() async {}

  void attachClient(final WebSocketChannel channel) {
    _incoming.add(WebSocketMeshSession(remotePeerId: 'relay', channel: channel));
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final endpoint = peer.endpointHints['ws'];
    if (endpoint == null) {
      throw MeshConnectionException(peer.peerId, 'no ws endpoint hint');
    }
    try {
      final channel = WebSocketChannel.connect(Uri.parse(endpoint));
      await channel.ready;
      return WebSocketMeshSession(
        remotePeerId: peer.peerId,
        channel: channel,
      );
    } catch (error) {
      throw MeshConnectionException(peer.peerId, '$error');
    }
  }

  Future<void> dispose() => _incoming.close();
}
