// ignore_for_file: lines_longer_as_80_chars

/// The in-process ACP embed transport (ADR 0026 §3): run `harnessd` as a
/// REAL `AcpStdioServer` over an in-memory duplex channel — no stdio, no
/// subprocess — and drive it through a real `AcpClient`.
///
/// This is the SDK embedding shape of ADR 0025 §3: apps (last_answer) get
/// the same wire protocol any external ACP client (Zed, pi) would speak,
/// with zero subprocess management. Consent policy (surfacing
/// `requestPermission` to a UI) stays product-side — pass a
/// [AcpPermissionHandler] or read the client's permission stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

import 'harness_acp_backend.dart';

/// An embedded, in-process harnessd daemon. `start()` runs the daemon and
/// performs the ACP handshake; `delegateTask` runs one prompt turn; the
/// raw [client] is exposed for surfaces the helper does not wrap.
final class HarnessEmbed {
  HarnessEmbed._(this._client, this._toServer, this._toClient);

  final AcpClient _client;
  final StreamController<List<int>> _toServer;
  final StreamController<List<int>> _toClient;

  /// The underlying ACP client (for surfaces [delegateTask] does not
  /// cover: streaming control, raw session management, permission UIs).
  AcpClient get client => _client;

  bool get isRunning => !_client.isClosed;

  /// Starts the daemon + client handshake over the in-memory channel.
  static Future<HarnessEmbed> start({
    required HarnessAcpBackend backend,
    AcpPermissionDelegate? permissionHandler,
  }) async {
    final toServer = StreamController<List<int>>();
    final toClient = StreamController<List<int>>();
    final server = AcpStdioServer(
      backend: backend,
      inputStream: toServer.stream,
      outputSink: _ChannelSink(toClient),
    );
    // The server loop reads the in-memory stream until the host stops.
    unawaited(server.run());
    final client = AcpClient(
      agentOutput: toClient.stream,
      agentInput: _ChannelSink(toServer),
      permissionHandler: permissionHandler,
    );
    await client.initialize();
    return HarnessEmbed._(client, toServer, toClient);
  }

  /// Creates a session for [cwd] (the delegated workspace). Sessions are
  /// keyed per workspace by the backend: a second `session/new` for the
  /// same cwd CONTINUES the live world (and restores it from the snapshot
  /// store after a host restart).
  Future<String> newSession(final String cwd) => _client.newSession(cwd: cwd);

  /// Runs one prompt turn — the user's task sentence as a host-injected
  /// decision. Progress streams to [onText] (agent text chunks, including
  /// the final `verdict:` line) and [onToolCall] (tool titles).
  Future<AcpStopReason> delegateTask(
    final String sessionId,
    final String task, {
    final void Function(String delta)? onText,
    final void Function(String title)? onToolCall,
  }) async {
    final result = await _client.promptText(
      sessionId,
      task,
      onUpdate: (final update) => switch (update) {
        AgentMessageChunk() => () {
          final content = update.content;
          if (content is AcpTextBlock && content.text.isNotEmpty) {
            onText?.call(content.text);
          }
        }(),
        ToolCallUpdate() => onToolCall?.call(update.title ?? 'tool'),
        _ => null,
      },
    );
    return result.stopReason;
  }

  /// Cancels in-flight work for a session (real: aborts generation).
  void cancel(final String sessionId) => _client.cancel(sessionId);

  /// Stops the daemon (closes both channel ends) and the client.
  Future<void> stop() async {
    await _client.dispose();
    if (!_toServer.isClosed) await _toServer.close();
    if (!_toClient.isClosed) await _toClient.close();
  }
}

/// A [StringSink] adapter that pushes utf8-encoded lines into a
/// [StreamController] — the in-memory stand-in for a subprocess pipe.
final class _ChannelSink implements StringSink {
  _ChannelSink(this._out);

  final StreamController<List<int>> _out;

  @override
  void write(final Object? obj) => _add('$obj');

  @override
  void writeln([final Object? obj = '']) => _add('$obj\n');

  @override
  void writeAll(
    final Iterable<Object?> objects, [
    final String separator = '',
  ]) => _add(objects.join(separator));

  @override
  void writeCharCode(final int charCode) => _add(String.fromCharCode(charCode));

  void _add(final String s) {
    if (!_out.isClosed) _out.add(utf8.encode(s));
  }
}
