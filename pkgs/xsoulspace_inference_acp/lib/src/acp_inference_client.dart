import 'dart:async';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// Spawns (or attaches to) an ACP agent subprocess and exposes it as an
/// [InferenceClient].
///
/// Each [infer] call runs one prompt turn in a fresh ACP session rooted at
/// the request's working directory, so prompts stay isolated — matching how
/// one-shot CLI agents (`codex exec`, `gemini -p`) behave.
///
/// Streaming ([streamStructuredText]) reuses a single long-lived connection
/// and forwards `agent_message_chunk` updates as partial-output events.
class AcpInferenceClient
    implements InferenceClient, StructuredTextStreamingInferenceClient {
  AcpInferenceClient({
    required String command,
    List<String> arguments = const [],
    this.id = 'acp',
    this.workingDirectory,
    this.environment,
    AcpPermissionDelegate? permissionHandler,
    Duration availabilityCacheTtl = const Duration(seconds: 30),
  })  : _command = command,
        _arguments = arguments,
        _permissionHandler = permissionHandler,
        _availabilityCacheTtl = availabilityCacheTtl;

  final String _command;
  final List<String> _arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final AcpPermissionDelegate? _permissionHandler;
  final Duration _availabilityCacheTtl;

  @override
  final String id;

  AcpClient? _client;
  Future<AcpClient>? _connecting;
  bool? _cachedAvailability;
  DateTime? _availabilityCheckedAt;

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
        InferenceTask.text,
        InferenceTask.implicitlyStructuredText,
      };

  @override
  bool get isAvailable => _cachedAvailability ?? false;

  @override
  Future<bool> refreshAvailability() async {
    final checkedAt = _availabilityCheckedAt;
    if (_cachedAvailability != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _availabilityCacheTtl) {
      return _cachedAvailability!;
    }
    try {
      final client = await _getOrConnect();
      _setAvailability(client != null);
      return _cachedAvailability!;
    } on Exception {
      _setAvailability(false);
      return false;
    }
  }

  @override
  Future<void> load() async {
    // Nothing to preload; the agent binary is spawned per connection.
  }

  @override
  void resetAvailabilityCache() {
    _cachedAvailability = null;
    _availabilityCheckedAt = null;
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request, {
    ToolRegistry? toolRegistry,
  }) async {
    final client = await _getOrConnect();
    if (client == null) {
      return InferenceResult.fail(
        code: 'agent_unavailable',
        message: 'ACP agent "$_command" could not be spawned',
      );
    }
    try {
      final sessionId = await client.newSession(
        cwd: request.workingDirectory.isEmpty
            ? (workingDirectory ?? '.')
            : request.workingDirectory,
      );
      final turn = await client.promptText(sessionId, request.prompt);
      return InferenceResult.ok(
        InferenceResponse(
          task: InferenceTask.text,
          meta: <String, dynamic>{
            'sessionId': sessionId,
            'stopReason': turn.stopReason.wire,
          },
        ),
      );
    } on StateError catch (error) {
      await _disposeClient();
      return InferenceResult.fail(code: 'acp_error', message: '$error');
    }
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    final InferenceRequest request,
  ) async {
    final client = await _getOrConnect();
    if (client == null) {
      throw StateError('ACP agent "$_command" could not be spawned');
    }
    final session = _AcpStreamSession(client, workingDirectory);
    session.start(request.prompt);
    return session;
  }

  /// Releases the agent process. Safe to call repeatedly; the next [infer]
  /// spawns a fresh agent.
  Future<void> dispose() => _disposeClient();

  void _setAvailability(final bool value) {
    _cachedAvailability = value;
    _availabilityCheckedAt = DateTime.now();
  }

  Future<AcpClient?> _getOrConnect() async {
    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;
    final connecting = _connecting;
    if (connecting != null) return connecting;
    final future = AcpClient.spawn(
      _command,
      _arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      permissionHandler: _permissionHandler,
    );
    _connecting = future;
    try {
      final client = await future;
      await client.initialize();
      _client = client;
      return client;
    } on Exception {
      return null;
    } finally {
      _connecting = null;
    }
  }

  Future<void> _disposeClient() async {
    final client = _client;
    _client = null;
    await client?.dispose();
  }
}

final class _AcpStreamSession implements InferenceStructuredTextStreamSession {
  _AcpStreamSession(this._client, this._workingDirectory);

  final AcpClient _client;
  final String? _workingDirectory;

  final _events =
      StreamController<InferenceStructuredTextStreamEvent>.broadcast();
  final _completer = Completer<InferenceResult<InferenceResponse>>();

  @override
  Stream<InferenceStructuredTextStreamEvent> get events => _events.stream;

  @override
  Future<InferenceResult<InferenceResponse>> get result => _completer.future;

  void start(final String prompt) {
    _run(prompt).ignore();
  }

  Future<void> _run(final String prompt) async {
    void emit(final InferenceStructuredTextStreamEvent event) {
      if (!_events.isClosed) _events.add(event);
    }

    emit(
      InferenceStructuredTextStreamEvent(
        type: InferenceStructuredTextStreamEventType.lifecycle,
        timestamp: DateTime.now(),
        lifecycleState: InferenceStructuredTextLifecycleState.started,
      ),
    );
    final buffer = StringBuffer();
    try {
      final sessionId = await _client.newSession(cwd: _workingDirectory ?? '.');
      final turn = await _client.promptText(
        sessionId,
        prompt,
        onUpdate: (update) {
          if (update is AgentMessageChunk) {
            final content = update.content;
            if (content is AcpTextBlock) {
              buffer.write(content.text);
              emit(
                InferenceStructuredTextStreamEvent(
                  type: InferenceStructuredTextStreamEventType.partialOutput,
                  timestamp: DateTime.now(),
                  textDelta: content.text,
                ),
              );
            }
          } else if (update is ToolCallUpdate) {
            emit(
              InferenceStructuredTextStreamEvent(
                type: InferenceStructuredTextStreamEventType.progress,
                timestamp: DateTime.now(),
                message: update.title ?? 'tool call ${update.toolCallId}',
                metadata: <String, dynamic>{'status': update.status},
              ),
            );
          }
        },
      );
      final result = InferenceResult.ok(
        InferenceResponse(
          task: InferenceTask.text,
          rawOutput: buffer.toString(),
          meta: <String, dynamic>{
            'sessionId': sessionId,
            'stopReason': turn.stopReason.wire,
          },
        ),
      );
      emit(
        InferenceStructuredTextStreamEvent(
          type: InferenceStructuredTextStreamEventType.completion,
          timestamp: DateTime.now(),
          completion: InferenceStructuredTextCompletion(result: result),
        ),
      );
      if (!_completer.isCompleted) _completer.complete(result);
    } on Object catch (error) {
      emit(
        InferenceStructuredTextStreamEvent(
          type: InferenceStructuredTextStreamEventType.error,
          timestamp: DateTime.now(),
          error: InferenceError(code: 'acp_error', message: '$error'),
        ),
      );
      if (!_completer.isCompleted) {
        _completer.complete(
          InferenceResult.fail(code: 'acp_error', message: '$error'),
        );
      }
    } finally {
      await _events.close();
    }
  }

  @override
  Future<void> cancel() async {
    // Turn-level cancel needs the active sessionId; the turn completes or
    // fails on its own for now.
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    if (!_completer.isCompleted) {
      _completer.complete(
        InferenceResult.fail(code: 'disposed', message: 'session disposed'),
      );
    }
  }
}
