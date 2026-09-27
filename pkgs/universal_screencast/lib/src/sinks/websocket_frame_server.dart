import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../frame.dart';
import '../frame_sink.dart';

/// A loopback WebSocket server that broadcasts frames to connected
/// consumers (operator UIs, agents, other processes).
///
/// Wire contract per frame: one **text** message with JSON metadata, then
/// one **binary** message with the payload. On a close with [error] every
/// client receives a `{error: …}` text message before the socket closes —
/// error-frame-then-close, never silence.
///
/// Auth follows the browser constraint that WebSockets cannot set headers
/// on upgrade: pass the token as `?token=` on the connect URI; a wrong or
/// missing token is refused with HTTP 401.
class WebSocketFrameServer implements FrameSink {
  /// Creates an unstarted server sink.
  WebSocketFrameServer({InternetAddress? address, this._port, this._authToken})
    : _address = address ?? InternetAddress.loopbackIPv4;

  final InternetAddress _address;
  final int? _port;
  final String? _authToken;
  final List<WebSocket> _clients = [];
  HttpServer? _server;
  bool _closed = false;

  @override
  String get id => 'ws-frames';

  @override
  List<String> get acceptedContentTypes => const ['*'];

  /// Number of currently connected consumers.
  int get clientCount => _clients.length;

  /// Binds the server; returns the connect URI (token included as a query
  /// parameter when configured).
  Future<Uri> start() async {
    if (_server != null) return connectUri;
    _server = await HttpServer.bind(_address, _port ?? 0);
    _server!.listen((request) => _handle(request).catchError((Object _) {}));
    return connectUri;
  }

  /// URI consumers connect to.
  Uri get connectUri {
    final server = _server;
    if (server == null) {
      throw StateError('WebSocketFrameServer is not started');
    }
    return Uri.parse(
      'ws://127.0.0.1:${server.port}/frames'
      '${_authToken == null ? '' : '?token=$_authToken'}',
    );
  }

  @override
  Future<void> push(Frame frame) async {
    if (_closed) throw SinkClosedException(id);
    final server = _server;
    if (server == null) {
      throw StateError('WebSocketFrameServer is not started');
    }
    final meta = jsonEncode({
      'sourceId': frame.sourceId,
      'sequence': frame.sequence,
      'revision': frame.revision,
      'byteLength': frame.bytes.length,
      'contentType': frame.contentType,
      'capturedAt': frame.capturedAt.toIso8601String(),
    });
    for (final client in List.of(_clients)) {
      client.add(meta);
      client.add(frame.bytes);
    }
  }

  @override
  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    for (final client in List.of(_clients)) {
      if (error != null) {
        client.add(jsonEncode({'error': error.toString()}));
      }
      await client.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      if (_closed) {
        await socket.close();
        return;
      }
      _clients.add(socket);
      socket.listen(null, onDone: () => _clients.remove(socket));
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  bool _isAuthorized(HttpRequest request) {
    if (_authToken == null) return true;
    return request.uri.queryParameters['token'] == _authToken;
  }
}
