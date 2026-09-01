// ignore_for_file: lines_longer_as_80_chars

/// Stage N3/N4 — the harness exposed as an ACP agent: `harnessd`.
///
/// Any ACP client (Zed, pi via stdio, last_answer) can address the harness:
/// `session/new` (cwd = the delegated workspace) → `session/prompt` (a free
/// task sentence, D8 workspace-convention oracle) → streaming
/// `session/update`s (generation moves + tool calls) → final verdict chunk.
///
/// Sessions persist a world snapshot per turn (P5 mechanics): the daemon can
/// die and resume. The daemon is TRANSPORT + host policy — the core learns
/// no ACP (D5).
///
/// Known limitation (recorded in PLAN.md N4): the write gate runs in `apply`
/// mode inside the delegated workspace; ACP permission round-trips land with
/// the M3/M4 hardening.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart'
    show OpenRouterInferenceClient, OpenRouterModelNames;

import 'coding_agent_runner.dart'
    show CodingAgentRunResult, runCodingAgentOnce, taskFromSentence;
import 'native_bridge/native_client.dart';

class HarnessAcpBackend implements AcpAgentBackend {
  HarnessAcpBackend({
    this.backend = 'open_router',
    this.model = 'deepseek/deepseek-v4-flash-0731',
  });

  /// `open_router` (native tool calls) or `apple_foundation_afm`.
  final String backend;
  final String model;

  final _sessions = <String, _Session>{};
  var _counter = 0;

  @override
  String get name => 'harnessd';

  @override
  String get version => '0.1.0';

  @override
  Map<String, Object?> get agentCapabilities => const {
    'loadSession': false,
  };

  ModelRouter? _buildRouter() {
    if (backend == 'open_router') {
      final apiKey = Platform.environment['OPENROUTER_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) return null;
      final router = ModelRouter(
        inferenceClientsBuilders: {
          OpenRouterModelNames.openRouter: () => OpenRouterInferenceClient(
            apiKey: apiKey,
            defaultModel: model,
          ),
        },
      );
      final modelId = ModelId('harnessd');
      router.models[modelId] = Model(id: modelId, name: OpenRouterModelNames.openRouter);
      return router;
    }
    final router = ModelRouter(
      inferenceClientsBuilders: {
        DefaultModelNames.appleFoundation: () => AppleFoundationNativeClient(),
      },
    );
    final modelId = ModelId('harnessd');
    router.models[modelId] = Model(
      id: modelId,
      name: DefaultModelNames.appleFoundation,
    );
    return router;
  }

  @override
  Future<String> createSession(AcpSessionNewRequest request) async {
    final id = 'sess_${++_counter}';
    final store = SnapshotStore();
    await store.open(
      '${Directory.systemTemp.path}/harnessd_$id/store',
    );
    _sessions[id] = _Session(
      cwd: request.cwd,
      store: store,
      router: _buildRouter(),
    );
    return id;
  }

  @override
  Future<AcpStopReason> prompt(
    AcpPromptRequest request, {
    required void Function(AcpSessionUpdate update) emit,
    required bool Function() isCancelled,
  }) async {
    final session = _sessions[request.sessionId];
    if (session == null) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('error: unknown session'),
        ),
      );
      return AcpStopReason.refusal;
    }
    final text = [
      for (final block in request.prompt)
        if (block is AcpTextBlock) block.text,
    ].join('\n').trim();
    if (text.isEmpty) {
      emit(AgentMessageChunk(content: const AcpTextBlock('empty prompt')));
      return AcpStopReason.refusal;
    }

    // D8: the workspace convention decides the criterion — no per-task code.
    final CodingAgentRunResult result;
    try {
      final task = taskFromSentence(
        text,
        workspace: Directory(session.cwd),
      );
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            'delegated: "${task.prompt}"\ncheck: '
            '${task.runCommand?.join(" ")}\n',
          ),
        ),
      );
      result = await runCodingAgentOnce(
        task: task,
        jail: Directory(session.cwd),
        handler: _Telemetry(emit, session),
        backend: '$backend:$model',
        router: session.router,
        actorModelId: session.router?.models.keys.first,
        restoredWorld: session.world,
        onSnapshot: (live) async {
          session.world = live;
          await session.store.save(
            live,
            name: 'current',
            meta: {'cwd': session.cwd},
          );
        },
      );
    } on StateError catch (e) {
      emit(AgentMessageChunk(content: AcpTextBlock('${e.message}')));
      return AcpStopReason.refusal;
    }

    emit(
      AgentMessageChunk(
        content: AcpTextBlock(
          '\nverdict: ${result.passed ? "PASS" : "FAIL"} '
          '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
          'tokens ${result.projectionTokens})'
          '${result.failureClass.isEmpty ? "" : "\n${result.failureClass}"}',
        ),
      ),
    );
    return result.passed ? AcpStopReason.endTurn : AcpStopReason.refusal;
  }

  @override
  Future<AcpPermissionOutcome> requestPermission(
    AcpPermissionRequest request,
  ) async {
    // N4 limitation: apply-mode within the delegated workspace for now.
    return AcpPermissionOutcome.allow;
  }

  @override
  void cancelSession(String sessionId) {
    // N4: cooperative cancellation lands with the M4 hardening; budgets
    // already fail closed (structured FAIL, never a hang).
  }

  @override
  Future<void> disposeSession(String sessionId) async {
    _sessions.remove(sessionId);
  }
}

class _Session {
  _Session({required this.cwd, required this.store, required this.router});
  final String cwd;
  final SnapshotStore store;
  final ModelRouter? router;
  World? world;
}

/// Streams one ACP update per generation: the tool calls the actor made and
/// a short text chunk. Pure observation — the response flows unchanged.
class _Telemetry implements GenerationHandler {
  _Telemetry(this.emit, this.session);
  final void Function(AcpSessionUpdate update) emit;
  final _Session session;
  final GenerationHandler _inner = DefaultGenerationHandler();

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = await _router(world, request);
    return response;
  }

  Future<ActorGenerateResponse> _router(
    World world,
    ActorGenerateRequest request,
  ) async {
    final inner = session.router == null
        ? throw StateError('no inference backend available for this daemon')
        : DefaultGenerationHandler(router: session.router!);
    final response = await inner.generate(world, request);
    for (final call in response.toolCalls) {
      emit(
        ToolCallUpdate(
          toolCallId: '${call.name.value}',
          status: 'completed',
          title: '${call.name.value}',
        ),
      );
    }
    final text = response.rawOutput ?? '';
    if (text.isNotEmpty) {
      emit(AgentMessageChunk(content: AcpTextBlock('$text ')));
    }
    return response;
  }
}
