import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal local WebSocket fan-out relay for the example app.
///
/// This is deliberately not a mesh authority: it only forwards opaque
/// frames between currently connected clients.
final class WebSocketMeshRelay {
  WebSocketMeshRelay({required this.port});

  final int port;
  final Set<WebSocketChannel> _clients = {};
  HttpServer? _server;

  Future<void> start() async {
    final handler = webSocketHandler((channel, _) {
      _clients.add(channel);
      channel.stream.listen(
        (message) {
          for (final client in _clients) {
            if (client != channel) client.sink.add(message);
          }
        },
        onDone: () => _clients.remove(channel),
        onError: (Object _) => _clients.remove(channel),
      );
    });
    _server = await shelf_io.serve(
      const shelf.Pipeline().addHandler(handler),
      InternetAddress.anyIPv4,
      port,
    );
  }

  Future<void> dispose() async {
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
  }
}
