import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'system_one_wire_decision_provider.dart';

/// Optional OpenRouter System One adapter for bounded finite choices.
///
/// Construction is explicit and performs no I/O. This adapter calls
/// `/api/v1/systemone`; it is independent from [OpenRouterInferenceClient] and
/// never uses the chat-completions endpoint.
///
/// Cancellation is enforced by the adapter, not by the server: a cancelled
/// request is blocked before dispatch or its late response is discarded, even
/// though the remote model cannot abort computation. [capabilities]
/// therefore reports `supportsCancellation: true` in the adapter-enforced
/// sense; hosts must not assume server-side compute abort.
///
/// The transport loop, retry bounds, and response validation are shared with
/// the local-server adapters in [SystemOneWireDecisionProvider].
final class OpenRouterSystemOneDecisionProvider
    extends SystemOneWireDecisionProvider {
  // Parameters resolve concrete defaults (endpoint, bounds, capability
  // facts) at this public boundary, so they cannot be plain super params.
  // ignore: use_super_parameters
  OpenRouterSystemOneDecisionProvider({
    required final String apiKey,
    required final String model,
    final Uri? endpoint,
    final http.Client? httpClient,
    final Duration timeout = const Duration(seconds: 30),
    final int maxTransientRetries = 0,
    final Duration retryDelay = const Duration(milliseconds: 100),
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
    final int maxStateUtf8Bytes = 1 << 20,
    final int maxRequestUtf8Bytes = 2 << 20,
    final int maxQuestionsPerRequest = 64,
  }) : super(
         apiKey: apiKey,
         model: model,
         endpoint:
             endpoint ?? Uri.parse('https://openrouter.ai/api/v1/systemone'),
         capabilities: DecisionProviderCapabilities(
           supportedQuestionKinds: const <DecisionQuestionKind>{
             DecisionQuestionKind.finiteChoice,
           },
           bounds: DecisionProviderBounds(
             maxStateUtf8Bytes: maxStateUtf8Bytes,
             maxRequestUtf8Bytes: maxRequestUtf8Bytes,
             maxQuestionsPerRequest: maxQuestionsPerRequest,
             maxOptionsPerQuestion: 255,
           ),
           executionLocation: DecisionExecutionLocation.hosted,
           networkRequirement: DecisionNetworkRequirement.required,
           supportsCancellation: true,
         ),
         providerId: 'openrouter_system_one',
         wireLabel: 'OpenRouter System One',
         diagnosticEventType: 'openrouter.system_one.post',
         httpClient: httpClient,
         timeout: timeout,
         maxTransientRetries: maxTransientRetries,
         retryDelay: retryDelay,
         onDiagnosticEvent: onDiagnosticEvent,
         maxStateUtf8Bytes: maxStateUtf8Bytes,
         maxRequestUtf8Bytes: maxRequestUtf8Bytes,
         maxQuestionsPerRequest: maxQuestionsPerRequest,
       );

  @override
  DecisionFailure? get readinessFailure => hasApiKey
      ? null
      : const DecisionFailure(
          code: DecisionFailureCode.authentication,
          message: 'An OpenRouter API key is required for hosted decisions',
        );
}
