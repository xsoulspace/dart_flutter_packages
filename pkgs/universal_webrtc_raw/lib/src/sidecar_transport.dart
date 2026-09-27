import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Byte-transport seam for the sidecar: JSON-lines in, JSON-lines out.
///
/// Implementations: [ProcessSidecarTransport] (spawns the Rust binary)
/// and in-memory fakes in tests. The client never knows which is which.
abstract interface class SidecarTransport {
  /// Decoded lines from the sidecar (handshake, responses, events).
  Stream<String> get lines;

  /// Writes one line to the sidecar.
  Future<void> writeLine(String line);

  /// Terminates the sidecar. Idempotent.
  Future<void> kill();
}

/// Spawns the Rust sidecar binary and adapts its stdio.
class ProcessSidecarTransport implements SidecarTransport {
  ProcessSidecarTransport._(this._process) {
    _lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    unawaited(
      _process.exitCode.then(
        (code) => onError?.call('sidecar exited with code $code'),
      ),
    );
  }

  /// Called when the sidecar's stderr produces a line or it exits.
  void Function(String)? onError;

  final Process _process;
  late final Stream<String> _lines;

  /// Spawns [binary] with [args]; `XS_WEBRTC_SIDECAR` env var is the
  /// conventional override for the binary path.
  static Future<ProcessSidecarTransport> start({
    String? binary,
    List<String> args = const [],
    void Function(String)? onError,
  }) async {
    final resolved =
        binary ??
        Platform.environment['XS_WEBRTC_SIDECAR'] ??
        'xs-webrtc-sidecar';
    final process = await Process.start(resolved, args);
    if (onError != null) {
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onError);
    }
    return ProcessSidecarTransport._(process);
  }

  @override
  Stream<String> get lines => _lines;

  /// Pending write chain: `IOSink.flush()` marks the sink bound while
  /// pending, so concurrent `writeLine`s must be serialized.
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<void> writeLine(String line) {
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
