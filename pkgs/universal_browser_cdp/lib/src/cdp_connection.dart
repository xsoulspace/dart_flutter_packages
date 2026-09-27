import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'automation_exceptions_export.dart';

/// One protocol event pushed by the endpoint (no request id).
class CdpEvent {
  /// Creates an event.
  const CdpEvent(this.method, this.params);

  /// Event method, e.g. `Page.screencastFrame`.
  final String method;

  /// Event parameters.
  final Map<String, Object?> params;

  @override
  String toString() => 'CdpEvent($method)';
}

/// A CDP error response.
class CdpProtocolException extends ProtocolException {
  /// Creates the exception from an error response `error` object.
  CdpProtocolException(Map<String, Object?> error)
    : super(
        error['message'] as String? ?? 'cdp error',
        code: error['code'] as int?,
        details: error,
      );
}

/// A WebSocket JSON-RPC connection to a CDP endpoint (browser or page).
///
/// Requests are correlated by incrementing ids; events are exposed on a
/// broadcast stream, filterable with [on]. After [close], every call
/// throws.
class CdpConnection {
  CdpConnection._(this._socket) {
    _socket.listen(
      _onData,
      onDone: _onDone,
      onError: _failAll,
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _events = StreamController<CdpEvent>.broadcast(sync: true);
  int _nextId = 0;
  bool _closed = false;

  /// Opens the connection. Throws [EndpointUnreachableException] when the
  /// socket cannot be established within [timeout].
  static Future<CdpConnection> connect(
    Uri wsUri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(wsUri.toString()).timeout(timeout);
    } on Object catch (error) {
      throw EndpointUnreachableException(
        'cannot connect to CDP endpoint $wsUri: $error',
        details: {'uri': wsUri.toString()},
      );
    }
    return CdpConnection._(socket);
  }

  /// Broadcast of all endpoint events.
  Stream<CdpEvent> get events => _events.stream;

  /// Events filtered by [method].
  Stream<CdpEvent> on(String method) =>
      _events.stream.where((event) => event.method == method);

  /// Whether [close] has been called or the socket died.
  bool get isClosed => _closed;

  /// Sends a request and completes with the `result` object.
  Future<Map<String, Object?>> send(
    String method, [
    Map<String, Object?>? params,
    Duration? timeout,
  ]) {
    if (_closed) {
      throw StateError('CdpConnection is closed');
    }
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    final future = completer.future;
    if (timeout != null) return future.timeout(timeout);
    return future;
  }

  void _onData(data) {
    if (data is! String) return;
    final Object? message;
    try {
      message = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = message['error'];
      if (error is Map<String, Object?>) {
        completer.completeError(CdpProtocolException(error));
      } else {
        completer.complete(
          message['result'] as Map<String, Object?>? ?? const {},
        );
      }
      return;
    }
    final method = message['method'];
    if (method is String) {
      _events.add(
        CdpEvent(
          method,
          message['params'] as Map<String, Object?>? ?? const {},
        ),
      );
    }
  }

  Future<void> _onDone() async {
    _closed = true;
    _failAll(const SocketException('cdp websocket closed'));
    await _events.close();
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  /// Closes the socket; pending requests fail.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    _failAll(const SocketException('cdp websocket closed by client'));
    await _events.close();
  }
}
