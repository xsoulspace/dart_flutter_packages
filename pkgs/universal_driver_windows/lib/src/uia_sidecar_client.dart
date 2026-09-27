import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// One asynchronous sidecar message (`event` envelope).
@immutable
final class UiaSidecarEvent {
  /// Creates an event.
  const UiaSidecarEvent(this.kind, this.payload);

  /// Event kind.
  final String kind;

  /// Full JSON payload.
  final Map<String, Object?> payload;
}

/// Transport seam for `uia-sidecar/1` — process in production, fakes in
/// tests. Same shape as the webrtc sidecar transport; kept local so the
/// Windows driver has no cross-domain dependency.
abstract interface class UiaSidecarTransport {
  /// Decoded lines from the sidecar.
  Stream<String> get lines;

  /// Writes one line to the sidecar.
  Future<void> writeLine(String line);

  /// Terminates the sidecar. Idempotent.
  Future<void> kill();
}

/// Spawns the Rust sidecar binary and adapts its stdio.
final class ProcessUiaSidecarTransport implements UiaSidecarTransport {
  ProcessUiaSidecarTransport._(this._process) {
    _lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    unawaited(
      _process.exitCode.then(
        (code) => onError?.call('uia sidecar exited with code $code'),
      ),
    );
  }

  /// Called when the sidecar's stderr produces a line or it exits.
  void Function(String line)? onError;

  final Process _process;
  late final Stream<String> _lines;
  Future<void> _writeQueue = Future<void>.value();

  /// Spawns [binary] with [args]; `XS_UIA_SIDECAR` is the conventional
  /// binary path override.
  static Future<ProcessUiaSidecarTransport> start({
    String? binary,
    List<String> args = const [],
    void Function(String line)? onError,
  }) async {
    final resolved =
        binary ?? Platform.environment['XS_UIA_SIDECAR'] ?? 'xs-uia-sidecar';
    final process = await Process.start(resolved, args);
    final transport = ProcessUiaSidecarTransport._(process);
    transport.onError = onError;
    return transport;
  }

  @override
  Stream<String> get lines => _lines;

  @override
  Future<void> writeLine(String line) {
    // IOSink.flush() marks the sink bound while pending; writes must be
    // serialized (see the webrtc sidecar transport for the full story).
    final result = _writeQueue.then((_) => _write(line));
    _writeQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _write(String line) async {
    _process.stdin.write('$line\n');
    await _process.stdin.flush();
  }

  @override
  Future<void> kill() async {
    _process.kill();
    await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return _process.exitCode;
      },
    );
  }
}

/// Correlated client for `uia-sidecar/1`.
///
/// Handshake validated on construction; [request] correlates by
/// incrementing ids; events surface on a broadcast stream.
class UiaSidecarClient {
  /// Creates a client over [transport].
  UiaSidecarClient(this._transport) {
    _subscription = _transport.lines.listen(_onLine, onDone: () {
      if (!_handshake.isCompleted) {
        _handshake.completeError(
          const UiaSidecarException('sidecar closed before handshake'),
        );
      }
      _failAll(const UiaSidecarException('sidecar closed'));
    });
  }

  final UiaSidecarTransport _transport;
  final _events = StreamController<UiaSidecarEvent>.broadcast();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _handshake = Completer<String>();
  StreamSubscription<String>? _subscription;
  int _nextId = 0;
  bool _closed = false;

  /// Completes with the sidecar's handshake version string.
  Future<String> get handshake => _handshake.future;

  /// Broadcast of asynchronous sidecar events.
  Stream<UiaSidecarEvent> get events => _events.stream;

  /// Sends [op] with [params] and completes with the `result` object.
  Future<Map<String, Object?>> request(
    String op, [
    Map<String, Object?>? params,
  ]) {
    if (_closed) throw StateError('UiaSidecarClient is closed');
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    final message = {
      'id': id,
      'op': op,
      if (params != null) ...params,
    };
    return _transport
        .writeLine(jsonEncode(message))
        .then((_) => completer.future);
  }

  /// Shuts the sidecar down politely, then kills the transport.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _transport
          .writeLine(jsonEncode({'id': ++_nextId, 'op': 'shutdown'}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on Object {
      // The sidecar may already be gone.
    }
    await _subscription?.cancel();
    await _transport.kill();
    _failAll(const UiaSidecarException('sidecar closed by client'));
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
    if (!_handshake.isCompleted && message['sidecar'] is String) {
      _handshake.complete(message['sidecar']! as String);
      return;
    }
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = message['error'];
      if (error != null) {
        completer.completeError(UiaSidecarException(error.toString()));
      } else {
        completer.complete(
          (message['result'] as Map<String, Object?>? ?? const {}),
        );
      }
      return;
    }
    final event = message['event'];
    if (event is String) {
      _events.add(UiaSidecarEvent(event, message));
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }
}

/// The sidecar answered with an error or broke the protocol.
class UiaSidecarException implements Exception {
  /// Creates the exception.
  const UiaSidecarException(this.message);

  final String message;

  @override
  String toString() => 'UiaSidecarException: $message';
}
