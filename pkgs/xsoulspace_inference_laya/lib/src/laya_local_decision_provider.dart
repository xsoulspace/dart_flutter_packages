import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/laya_server.dart';

import 'laya_serve_runtime.dart';

/// Decision provider bound to the local [LayaServeRuntime].
///
/// Composes the loopback [LayaServerDecisionProvider] (the shared System One
/// wire adapter, which already reports honest `local`/`none` capability
/// facts) with the runtime's readiness: when the server is not answering,
/// decisions return a typed `DecisionUnavailable` instead of a network
/// error.
///
/// The wire adapter is owned, not wrapped in a second class: hosts bind this
/// object where they would bind the hosted OpenRouter System One adapter
/// (see the harness `jevDecisionBinding` seam) and local-only policy picks
/// it up through capability facts alone.
final class LayaLocalDecisionProvider implements DecisionProvider {
  LayaLocalDecisionProvider({
    required this.runtime,
    final String? apiKey,
    final String model = 'laya',
    final Uri? endpoint,
    final Duration timeout = const Duration(seconds: 10),
    final int maxTransientRetries = 1,
    final http.Client? httpClient,
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
  }) : _delegate = LayaServerDecisionProvider(
         apiKey: apiKey,
         model: model,
         endpoint: endpoint,
         timeout: timeout,
         maxTransientRetries: maxTransientRetries,
         httpClient: httpClient,
         onDiagnosticEvent: onDiagnosticEvent,
       );

  final LayaServeRuntime runtime;
  final LayaServerDecisionProvider _delegate;

  @override
  String get id => 'laya_local';

  @override
  DecisionProviderCapabilities get capabilities => _delegate.capabilities;

  @override
  DecisionProviderReadiness get readiness {
    final runtimeReadiness = switch (runtime.status.$1) {
      LayaRuntimeState.ready => const DecisionProviderReadiness(
        state: DecisionReadinessState.ready,
      ),
      LayaRuntimeState.stopped => const DecisionProviderReadiness(
        state: DecisionReadinessState.disposed,
        reasonCode: 'runtime_stopped',
        message: 'The local laya-serve runtime was stopped',
      ),
      _ => DecisionProviderReadiness(
        state: DecisionReadinessState.unavailable,
        reasonCode: 'server_not_running',
        message: runtime.status.$2 ?? 'No local laya-serve is answering',
      ),
    };
    if (runtimeReadiness.isReady) return _delegate.readiness;
    return runtimeReadiness;
  }

  /// The decision wire. A detached runtime surfaces as typed unavailable;
  /// callers that want auto-start compose [LayaServeRuntime.ensureRunning]
  /// explicitly — readiness getters never spawn or probe.
  @override
  Future<DecisionOutcome> decide(final DecisionRequest request) async {
    if (!runtime.isReady) {
      return DecisionUnavailable(
        correlation: request.correlation,
        failure: DecisionFailure(
          code: DecisionFailureCode.unavailable,
          message: readiness.message,
          retryable: true,
        ),
      );
    }
    return _delegate.decide(request);
  }

  @override
  Future<void> cancel(final DecisionCancellationId cancellationId) =>
      _delegate.cancel(cancellationId);

  /// Stops the runtime (killing only spawned processes) and disposes the
  /// wire adapter.
  @override
  Future<void> dispose() async {
    await _delegate.dispose();
    await runtime.dispose();
  }
}
