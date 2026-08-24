import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'addressed_relay_protocol.dart';

/// Reusable addressed WebSocket relay.
///
/// Routes opaque frames between registered peers. It never inspects mesh
/// payload contents and has no conflict-resolution authority.
final class AddressedRelayServer {
  AddressedRelayServer({required this.port});

  final int port;
  final Map<String, WebSocketChannel> _clients = {};
  HttpServer? _server;

  Future<int> start() async {
    final handler = webSocketHandler((channel, _) {
      String? peerId;
      channel.stream.listen(
        (message) {
          final envelope = AddressedRelayProtocol.decode(message as List<int>);
          if (envelope.kind == AddressedRelayProtocol.registerKind) {
            peerId = envelope.fromPeerId;
            _clients[peerId!] = channel;
            return;
          }
          if (peerId == null || envelope.fromPeerId != peerId) return;
          _clients[envelope.toPeerId]?.sink.add(message);
        },
        onDone: () {
          if (peerId != null) _clients.remove(peerId);
        },
        onError: (_) {
          if (peerId != null) _clients.remove(peerId);
        },
      );
    });
    _server = await shelf_io.serve(
      const shelf.Pipeline().addHandler(handler),
      InternetAddress.anyIPv4,
      port,
    );
    return _server!.port;
  }

  Future<void> dispose() async {
    for (final client in List.of(_clients.values)) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
  }
}
