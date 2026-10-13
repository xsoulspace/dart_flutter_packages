import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'acp_session_persistence.dart';

/// Spawns (or attaches to) an ACP agent subprocess and exposes it as an
/// [InferenceClient].
///
/// Calls stay isolated by default. An explicitly supplied [conversationKey]
/// retains one session per working directory and reloads it after transport
/// reconnect; failure to resume refuses rather than silently forking.
///
/// Streaming ([streamStructuredText]) reuses a single long-lived connection
/// and forwards `agent_message_chunk` updates as partial-output events.
class AcpInferenceClient
    implements InferenceClient, StructuredTextStreamingInferenceClient {
  AcpInferenceClient({
    required this._command,
    this._arguments = const [],
    this.id = 'acp',
    this.workingDirectory,
    this.environment,
    this._permissionHandler,
    this._availabilityCacheTtl = const Duration(seconds: 30),
    this.clientServices,
    this.conversationKey,
    this.clientFactory,
    this.boundMcpServers,
    this.sessionPersistence,
    this.providerIdentity,
  });

  final String _command;
  final List<String> _arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final AcpPermissionDelegate? _permissionHandler;
  final Duration _availabilityCacheTtl;
  final AcpClientServices? clientServices;

  /// Owner-supplied conversation identity; never inferred from model/transport.
  final String? conversationKey;
  final AcpSessionPersistence? sessionPersistence;
  final String? providerIdentity;
  final Future<AcpClient> Function()? clientFactory;

  /// References existing authorized host MCP servers; no catalog copy.
  final List<Map<String, Object?>> Function(ToolRegistry registry)?
  boundMcpServers;
  final Map<String, AcpSessionReference> _sessions = {};
  final Map<String, AcpSessionBinding> _pendingRebinds = {};
  final Map<String, String> _startingServers = {};
  final Map<String, AcpClient> _sessionTransports = {};
  final Set<String> _activeSessions = {};

  final Map<String, Future<String>> _sessionStarts = {};
  final Map<String, String> _sessionServers = {};
  int _cancelEpoch = 0;

  Future<String> _sessionFor(
    AcpClient client,
    String cwd,
    List<Map<String, Object?>> servers, {
    bool reconcile = false,
  }) async {
    if (sessionPersistence != null &&
        (conversationKey == null || conversationKey!.isEmpty)) {
      throw const AcpSessionPersistenceRefusal('conversation_key_required');
    }
    if (conversationKey == null) {
      return client.newSession(cwd: cwd, mcpServers: servers);
    }
    if (conversationKey!.isEmpty) throw StateError('conversation_key_required');
    final serverRevision = jsonEncode(_canonical(servers));
    if (_pendingRebinds.containsKey(cwd) && !reconcile) {
      throw const AcpSessionPersistenceRefusal('acp_session_rebind_pending');
    }
    if (_sessionServers[cwd] != null &&
        _sessionServers[cwd] != serverRevision &&
        sessionPersistence?.rebind == null) {
      throw StateError('acp_session_server_binding_changed');
    }
    final pending = _sessionStarts[cwd];
    if (pending != null) {
      if (_startingServers[cwd] != serverRevision) {
        throw const AcpSessionPersistenceRefusal('acp_session_rebind_busy');
      }
      return pending;
    }
    final capturedServers = (jsonDecode(serverRevision) as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    final future = _resolveSession(
      client,
      cwd,
      capturedServers,
      serverRevision,
    );
    _startingServers[cwd] = serverRevision;
    _sessionStarts[cwd] = future;
    try {
      final session = await future;
      _sessionServers[cwd] = serverRevision;
      _sessionTransports[cwd] = client;
      return session;
    } finally {
      // The stored future has already settled; removing it is not a new task.
      // ignore: unawaited_futures
      _sessionStarts.remove(cwd);
      _startingServers.remove(cwd);
    }
  }

  Future<String> _resolveSession(
    AcpClient client,
    String cwd,
    List<Map<String, Object?>> servers,
    String serverRevision,
  ) async {
    final persistence = sessionPersistence;
    final identity = providerIdentity;
    if (persistence != null && (identity == null || identity.isEmpty)) {
      throw const AcpSessionPersistenceRefusal(
        'acp_provider_identity_required',
      );
    }
    final binding = AcpSessionBinding(
      conversationKey: conversationKey!,
      workingDirectory: cwd,
      providerIdentity: identity ?? id,
      descriptorRevision: sha256
          .convert(utf8.encode(serverRevision))
          .toString(),
    );
    final remembered = _sessions[cwd];
    final previous = remembered ?? await persistence?.read(binding);
    if (previous != null && !previous.binding.matches(binding)) {
      return _rebindSession(client, cwd, servers, previous, binding);
    }
    if (persistence != null &&
        !await persistence.authorize(binding, previous)) {
      throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
    }
    if (remembered != null && identical(_sessionTransports[cwd], client)) {
      return remembered.sessionId;
    }
    final session = previous == null
        ? await client.newSession(cwd: cwd, mcpServers: servers)
        : await client.loadSession(
            previous.sessionId,
            cwd: cwd,
            mcpServers: servers,
          );
    if (previous != null && session != previous.sessionId) {
      throw const AcpSessionPersistenceRefusal('acp_session_resume_mismatch');
    }
    // Retain an acknowledged remote reference even if its durable save fails.
    // A retry may save/load that same reference, never create another session.
    final acknowledged = AcpSessionReference(
      binding: binding,
      sessionId: session,
    );
    _sessions[cwd] = acknowledged;
    _sessionServers[cwd] = serverRevision;
    if (persistence != null) {
      if (!await persistence.authorize(binding, acknowledged)) {
        throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
      }
      await persistence.acknowledge?.call(acknowledged);
      if (!await persistence.authorize(binding, acknowledged)) {
        throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
      }
      try {
        await persistence.save(acknowledged);
      } on Object {
        throw const AcpSessionPersistenceRefusal(
          'acp_session_persistence_failed',
        );
      }
      if (!await persistence.authorize(
        binding,
        AcpSessionReference(binding: binding, sessionId: session),
      )) {
        throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
      }
    }
    return session;
  }

  Future<String> _rebindSession(
    AcpClient client,
    String cwd,
    List<Map<String, Object?>> servers,
    AcpSessionReference previous,
    AcpSessionBinding next,
  ) async {
    final persistence = sessionPersistence!;
    final port = persistence.rebind;
    if (port == null ||
        previous.binding.conversationKey != next.conversationKey ||
        previous.binding.workingDirectory != next.workingDirectory ||
        previous.binding.providerIdentity != next.providerIdentity ||
        previous.binding.descriptorRevision == next.descriptorRevision) {
      throw const AcpSessionPersistenceRefusal(
        'acp_stored_session_binding_changed',
      );
    }
    final oldTransport = _sessionTransports[cwd];
    if (_activeSessions.contains(previous.sessionId) ||
        (oldTransport != null && !oldTransport.isClosed)) {
      throw const AcpSessionPersistenceRefusal('acp_session_rebind_busy');
    }
    final epoch = _cancelEpoch;
    void current() {
      if (epoch != _cancelEpoch) {
        throw const AcpSessionPersistenceRefusal('acp_cancelled');
      }
    }

    // Retain the original scope even on ACK/commit failure. Uncertainty blocks
    // another load or prompt; native reconciliation is an explicit owner act.
    _sessions[cwd] = previous;
    _pendingRebinds[cwd] = next;
    current();
    final ticket = await port.stage(previous, next);
    current();
    if (ticket == null) {
      _pendingRebinds.remove(cwd);
      throw const AcpSessionPersistenceRefusal('acp_session_rebind_refused');
    }
    Future<void> authorized() async {
      current();
      final allowed = await port.authorize(ticket, previous, next);
      current();
      if (!allowed) {
        throw const AcpSessionPersistenceRefusal('acp_session_rebind_refused');
      }
    }

    await authorized();
    final grant = await persistence.authorize(next, null);
    await authorized();
    if (!grant) {
      throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
    }
    final session = await client.loadSession(
      previous.sessionId,
      cwd: cwd,
      mcpServers: servers,
    );
    await authorized();
    if (session != previous.sessionId) {
      throw const AcpSessionPersistenceRefusal('acp_session_resume_mismatch');
    }
    final acknowledged = AcpSessionReference(binding: next, sessionId: session);
    final ackGrant = await persistence.authorize(next, acknowledged);
    await authorized();
    if (!ackGrant) {
      throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
    }
    await persistence.acknowledge?.call(acknowledged);
    await authorized();
    final committed = await port.commit(ticket, previous, acknowledged);
    await authorized();
    if (!committed) {
      throw const AcpSessionPersistenceRefusal(
        'acp_session_rebind_commit_failed',
      );
    }
    final finalGrant = await persistence.authorize(next, acknowledged);
    await authorized();
    if (!finalGrant) {
      throw const AcpSessionPersistenceRefusal('acp_session_grant_refused');
    }
    _sessions[cwd] = acknowledged;
    _pendingRebinds.remove(cwd);
    return session;
  }

  /// Explicit native-authorized recovery of a known uncertain descriptor
  /// transition. Loads only its original session ID; never dispatches a prompt.
  Future<AcpSessionReference> reconcileSessionBinding({
    required String workingDirectory,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    final pending = _pendingRebinds[workingDirectory];
    final revision = sha256
        .convert(utf8.encode(jsonEncode(_canonical(mcpServers))))
        .toString();
    if (pending == null || pending.descriptorRevision != revision) {
      throw const AcpSessionPersistenceRefusal(
        'acp_session_rebind_reconciliation_scope',
      );
    }
    final previous = _sessions[workingDirectory];
    final oldTransport = _sessionTransports[workingDirectory];
    if (previous == null ||
        _sessionStarts.containsKey(workingDirectory) ||
        _activeSessions.contains(previous.sessionId) ||
        (oldTransport != null && !oldTransport.isClosed)) {
      throw const AcpSessionPersistenceRefusal('acp_session_rebind_busy');
    }
    final client = await _getOrConnect();
    if (client == null) {
      throw const AcpSessionPersistenceRefusal('agent_unavailable');
    }
    try {
      await _sessionFor(client, workingDirectory, mcpServers, reconcile: true);
      return _sessions[workingDirectory]!;
    } on Object {
      await _disposeClient();
      rethrow;
    }
  }

  void cancelActive() {
    _cancelEpoch++;
    final client = _client;
    if (client != null) _activeSessions.forEach(client.cancel);
  }

  @override
  final String id;

  AcpClient? _client;
  Future<AcpClient?>? _connecting;
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
    final epoch = _cancelEpoch;
    final servers = toolRegistry == null || toolRegistry.tools.isEmpty
        ? const <Map<String, Object?>>[]
        : boundMcpServers?.call(toolRegistry);
    if (servers == null ||
        (toolRegistry != null &&
            toolRegistry.tools.isNotEmpty &&
            servers.isEmpty)) {
      return InferenceResult.fail(
        code: 'acp_tool_registry_unbound',
        message:
            'Install the registry on an authorized host MCP server '
            'before ACP dispatch',
      );
    }
    final cwd = request.workingDirectory.isEmpty
        ? (workingDirectory ?? '.')
        : request.workingDirectory;
    if (_pendingRebinds.containsKey(cwd)) {
      return InferenceResult.fail(
        code: 'acp_session_rebind_pending',
        message: 'Explicit native reconciliation required',
      );
    }
    final client = await _getOrConnect();
    if (client == null) {
      return InferenceResult.fail(
        code: 'agent_unavailable',
        message: 'ACP agent "$_command" could not be spawned',
      );
    }
    try {
      final sessionId = await _sessionFor(
        client,
        request.workingDirectory.isEmpty
            ? (workingDirectory ?? '.')
            : request.workingDirectory,
        servers,
      );
      if (epoch != _cancelEpoch) {
        return InferenceResult.fail(
          code: 'acp_cancelled',
          message: 'Cancelled before prompt dispatch',
        );
      }
      if (!_activeSessions.add(sessionId)) {
        return InferenceResult.fail(
          code: 'acp_session_busy',
          message: 'This conversation already has an active turn',
        );
      }
      final buffer = StringBuffer();
      final AcpPromptTurnResult turn;
      try {
        turn = await client.prompt(
          sessionId,
          _promptBlocks(request),
          onUpdate: (update) {
            if (update is AgentMessageChunk && update.content is AcpTextBlock) {
              buffer.write((update.content as AcpTextBlock).text);
            }
          },
        );
      } finally {
        _activeSessions.remove(sessionId);
      }
      if (epoch != _cancelEpoch) {
        return InferenceResult.fail(
          code: 'acp_cancelled',
          message: 'Turn cancelled',
        );
      }
      return InferenceResult.ok(
        InferenceResponse(
          task: InferenceTask.text,
          rawOutput: buffer.toString(),
          meta: <String, dynamic>{
            'sessionId': sessionId,
            'stopReason': turn.stopReason.wire,
          },
        ),
      );
    } on AcpSessionPersistenceRefusal catch (error) {
      if (error.code != 'acp_session_rebind_busy') await _disposeClient();
      return InferenceResult.fail(code: error.code, message: error.code);
    } on Object catch (error) {
      await _disposeClient();
      return InferenceResult.fail(code: 'acp_error', message: '$error');
    }
  }

  @override
  Future<InferenceStructuredTextStreamSession> streamStructuredText(
    final InferenceRequest request,
  ) async {
    final cwd = request.workingDirectory.isEmpty
        ? (workingDirectory ?? '.')
        : request.workingDirectory;
    if (_pendingRebinds.containsKey(cwd)) {
      throw const AcpSessionPersistenceRefusal('acp_session_rebind_pending');
    }
    final client = await _getOrConnect();
    if (client == null) {
      throw StateError('ACP agent "$_command" could not be spawned');
    }
    final sessionId = await _sessionFor(
      client,
      request.workingDirectory.isEmpty
          ? (workingDirectory ?? '.')
          : request.workingDirectory,
      const [],
    );
    if (!_activeSessions.add(sessionId)) throw StateError('acp_session_busy');
    final session = _AcpStreamSession(
      client,
      sessionId,
      () => _activeSessions.remove(sessionId),
    );
    session.start(_promptBlocks(request));
    return session;
  }

  /// Releases the agent process. Safe to call repeatedly; the next [infer]
  /// spawns a fresh agent.
  Future<void> dispose() {
    cancelActive();
    return _disposeClient();
  }

  void _setAvailability(final bool value) {
    _cachedAvailability = value;
    _availabilityCheckedAt = DateTime.now();
  }

  Future<void>? _transportDisposal;

  Future<AcpClient?> _getOrConnect() async {
    // A failed/unknown native settlement cannot silently open another service.
    await _transportDisposal;
    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;
    final connecting = _connecting;
    if (connecting != null) return connecting;
    final future = _connect();
    _connecting = future;
    try {
      return await future;
    } finally {
      if (identical(_connecting, future)) _connecting = null;
    }
  }

  Future<AcpClient?> _connect() async {
    final epoch = _cancelEpoch;
    AcpClient? opened;
    try {
      final client =
          await (clientFactory?.call() ??
              AcpClient.spawn(
                _command,
                _arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                permissionHandler: _permissionHandler,
                services: clientServices,
              ));
      opened = client;
      await client.initialize();
      if (epoch != _cancelEpoch) {
        await _disposeTransport(client);
        return null;
      }
      _client = client;
      return client;
    } on Object {
      if (opened != null) await _disposeTransport(opened);
      return null;
    }
  }

  Future<void> _disposeClient() async {
    final client = _client;
    _client = null;
    if (client != null) await _disposeTransport(client);
    await _transportDisposal;
  }

  Future<void> _disposeTransport(AcpClient client) async {
    final disposal = _transportDisposal ??= client.dispose();
    await disposal;
    // Clear only after actual successful disposal. Preserve failure as a gate.
    if (identical(_transportDisposal, disposal)) _transportDisposal = null;
  }
}

// ACP prompt content has no native system/assistant/tool role channel. Keep
// declared roles/content as serialized text, without inventing privilege or a
// stored transcript. Recompute solely from this request's projected cut.
List<AcpContentBlock> _promptBlocks(InferenceRequest request) {
  final messages = request.messages.isNotEmpty
      ? request.messages
      : SituationMessagesCodec.render(
          prompt: request.prompt,
          systemPrompt: request.systemPrompt,
          fragments: request.contextFragments,
        ).map(ChatMessage.fromJson).toList();
  return [
    for (final message in messages) AcpTextBlock(jsonEncode(message.toJson())),
  ];
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

final class _AcpStreamSession implements InferenceStructuredTextStreamSession {
  _AcpStreamSession(this._client, this._sessionId, this._settled);

  final AcpClient _client;
  final String _sessionId;
  final void Function() _settled;
  bool _cancelled = false;

  final _events =
      StreamController<InferenceStructuredTextStreamEvent>.broadcast();
  final _completer = Completer<InferenceResult<InferenceResponse>>();

  @override
  Stream<InferenceStructuredTextStreamEvent> get events => _events.stream;

  @override
  Future<InferenceResult<InferenceResponse>> get result => _completer.future;

  void start(final List<AcpContentBlock> prompt) {
    _run(prompt).ignore();
  }

  Future<void> _run(final List<AcpContentBlock> prompt) async {
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
      final sessionId = _sessionId;
      final turn = await _client.prompt(
        sessionId,
        prompt,
        onUpdate: (update) {
          if (_cancelled) return;
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
      if (_cancelled) throw StateError('acp_cancelled');
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
      _settled();
      await _events.close();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _client.cancel(_sessionId);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _events.close();
    if (!_completer.isCompleted) {
      _completer.complete(
        InferenceResult.fail(code: 'disposed', message: 'session disposed'),
      );
    }
  }
}
