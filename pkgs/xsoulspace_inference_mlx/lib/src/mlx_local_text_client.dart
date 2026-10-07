import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'mlx_chat_wire.dart';
import 'mlx_serve_runtime.dart';

export 'mlx_chat_wire.dart'
    show
        HttpMlxChatEndpoint,
        MlxChatEndpoint,
        MlxChatException,
        MlxChatMessage,
        MlxChatRequest,
        MlxChatResult,
        MlxWireDiagnostic;

/// A local small text model (MLX server on loopback) bound as an
/// [InferenceClient].
///
/// Composes the health-gated [MlxServeRuntime] with the OpenAI-compatible
/// chat wire: availability is the runtime's honest local snapshot (getters
/// never spawn or probe), `load`/`refreshAvailability` are the one
/// asynchronous readiness operation, and a detached runtime surfaces as a
/// typed unavailable result — never a network error, never a fake ready.
///
/// Capability facts mirror the laya decision provider's honesty about
/// locality: the model runs on this machine, dispatch never leaves the
/// loopback, and the client supports the plain [InferenceTask.text] task
/// only. Structured output is the caller's contract with the prompt, not a
/// wire guarantee (v1); tool calling is out of scope for a local drafting
/// model.
///
/// Only [InferenceTask.text] requests cross this client. Requests carry
/// `maxTokens`/`temperature` when set; when absent, the constructor-level
/// defaults apply (a conservative generation budget and greedy decoding —
/// deterministic drafts are the point).
final class MlxLocalTextClient implements InferenceClient {
  MlxLocalTextClient({
    required this.runtime,
    final MlxChatEndpoint? endpoint,
    final String model = 'local',
    this.defaultMaxTokens = 320,
    this.defaultTemperature = 0.0,
    final Duration timeout = const Duration(seconds: 120),
    final int maxTransientRetries = 1,
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
    final http.Client? httpClient,
  }) : _endpoint =
           endpoint ??
           HttpMlxChatEndpoint(
             endpoint: MlxServeRuntime.defaultEndpoint(),
             model: model,
             timeout: timeout,
             maxTransientRetries: maxTransientRetries,
             onDiagnosticEvent: onDiagnosticEvent,
             httpClient: httpClient,
           ),
       _model = model;

  final MlxServeRuntime runtime;

  final String _model;
  final int defaultMaxTokens;
  final double defaultTemperature;

  final MlxChatEndpoint _endpoint;

  @override
  String get id => 'mlx_local';

  @override
  Set<InferenceTask> get supportedTasks => const <InferenceTask>{
    InferenceTask.text,
  };

  /// The runtime's local snapshot — no I/O, no probes, no spawning.
  @override
  bool get isAvailable => runtime.isReady;

  @override
  Future<bool> refreshAvailability() => runtime.ensureRunning();

  @override
  Future<void> load() async {
    await runtime.ensureRunning();
  }

  @override
  void resetAvailabilityCache() {
    // The runtime keeps no availability cache: status is a live snapshot.
  }

  @override
  Future<InferenceResult<InferenceResponse>> infer(
    final InferenceRequest request, {
    final ToolRegistry? toolRegistry,
  }) async {
    if (request.task != InferenceTask.text) {
      return InferenceResult.fail(
        code: 'unsupported_task',
        message:
            'mlx_local supports InferenceTask.text only '
            '(requested ${request.task.name})',
      );
    }
    if (!runtime.isReady) {
      final issues = readiness.issues;
      return InferenceResult.fail(
        code: 'unavailable',
        message: issues.isEmpty
            ? 'No local MLX server is answering'
            : issues.first.message,
        details: <String, Object?>{'retryable': true},
      );
    }
    final messages = <MlxChatMessage>[
      if (request.systemPrompt.isNotEmpty)
        MlxChatMessage(role: 'system', content: request.systemPrompt),
      MlxChatMessage(role: 'user', content: request.prompt),
    ];
    final MlxChatResult result;
    try {
      result = await _endpoint.complete(
        MlxChatRequest(
          model: _model,
          messages: messages,
          maxTokens: request.maxTokens ?? defaultMaxTokens,
          temperature: request.temperature ?? defaultTemperature,
          stop: request.stopSequences,
        ),
      );
    } on MlxChatException catch (error) {
      return InferenceResult.fail(
        code: error.retryable ? 'transport' : 'invalid_response',
        message: error.message,
        details: <String, Object?>{'retryable': error.retryable},
      );
    }
    return InferenceResult.ok(
      InferenceResponse(
        task: InferenceTask.text,
        rawOutput: result.text,
        meta: <String, dynamic>{
          'usage': <String, dynamic>{
            'prompt_tokens': ?result.promptTokens,
            'completion_tokens': ?result.completionTokens,
          },
          'model': ?result.resolvedModel,
          'finish_reason': ?result.finishReason,
        },
      ),
    );
  }

  /// The honest readiness surface (runtime snapshot + reason).
  InferenceReadinessSnapshot get readiness {
    final (state, reason) = runtime.status;
    return switch (state) {
      LocalServeState.ready => const InferenceReadinessSnapshot(
        state: InferenceReadinessState.ready,
      ),
      LocalServeState.stopped => InferenceReadinessSnapshot(
        state: InferenceReadinessState.unavailable,
        issues: const <InferenceReadinessIssue>[
          InferenceReadinessIssue(
            code: 'runtime_stopped',
            message: 'The local MLX serve runtime was stopped',
          ),
        ],
      ),
      _ => InferenceReadinessSnapshot(
        state: InferenceReadinessState.unavailable,
        issues: <InferenceReadinessIssue>[
          InferenceReadinessIssue(
            code: 'server_not_running',
            message: reason ?? 'No local MLX server is answering',
          ),
        ],
      ),
    };
  }

  /// Stops the runtime (killing only spawned processes) and disposes the
  /// wire adapter. Not part of the InferenceClient contract — hosts that
  /// compose runtimes own shutdown.
  Future<void> dispose() async {
    await _endpoint.dispose();
    await runtime.dispose();
  }
}
