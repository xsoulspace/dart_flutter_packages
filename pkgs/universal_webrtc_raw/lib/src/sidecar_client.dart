import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'sidecar_exceptions.dart';
import 'sidecar_transport.dart';

/// One asynchronous sidecar message (`event` envelope).
@immutable
class SidecarEvent {
  /// Creates an event.
  const SidecarEvent(this.kind, this.payload);

  /// Event kind: `open`, `ice`, `closed`.
  final String kind;

  /// Full JSON payload (includes `peerId` and event-specific fields).
  final Map<String, Object?> payload;

  @override
  String toString() => 'SidecarEvent($kind $payload)';
}

/// Correlated client for `xs-webrtc-sidecar/1`.
///
/// Handshake is validated on construction; [request] correlates by
/// incrementing ids; events surface on a broadcast stream. After [close]
/// every call throws.
class SidecarClient {
  SidecarClient(this._transport) {
    _subscription = _transport.lines.listen(
      _onLine,
      onDone: () {
        if (!_handshake.isCompleted) {
          _handshake.completeError(
            const SidecarException('sidecar closed before handshake'),
          );
        }
        _failAll(const SidecarException('sidecar closed'));
      },
      onError: (Object error) {
        _failAll(SidecarException('sidecar stream error: $error'));
      },
    );
  }

  final SidecarTransport _transport;
  final _events = StreamController<SidecarEvent>.broadcast();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _handshake = Completer<String>();
  StreamSubscription<String>? _subscription;
  int _nextId = 0;
  bool _closed = false;

  /// Completes with the sidecar's handshake version string.
  Future<String> get handshake => _handshake.future;

  /// Broadcast of asynchronous sidecar events.
  Stream<SidecarEvent> get events => _events.stream;

  /// Sends [op] with [params] and completes with the `result` object.
  Future<Map<String, Object?>> request(
    String op, [
    Map<String, Object?>? params,
  ]) {
    if (_closed) throw StateError('SidecarClient is closed');
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final message = {'id': id, 'op': op, ...?params};
    return _transport
        .writeLine(jsonEncode(message))
        .then((_) => completer.future);
  }

  /// Shuts the sidecar down politely, then kills the transport.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _transport.writeLine(
        jsonEncode({'id': ++_nextId, 'op': 'shutdown'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on Object {
      // The sidecar may already be gone.
    }
    await _subscription?.cancel();
    await _transport.kill();
    _failAll(const SidecarException('sidecar closed by client'));
    await _events.close();
  }

  void _onLine(String line) {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    if (_handshake.isCompleted == false && message['sidecar'] is String) {
      _handshake.complete(message['sidecar']! as String);
      return;
    }
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = message['error'];
      if (error != null) {
        completer.completeError(
          SidecarException(error.toString(), details: {'op': id}),
        );
      } else {
        completer.complete(
          message['result'] as Map<String, Object?>? ?? const {},
        );
      }
      return;
    }
    final event = message['event'];
    if (event is String) {
      _events.add(SidecarEvent(event, message));
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}
