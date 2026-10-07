import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'system_one_wire_decision_provider.dart';

/// Adapter for a [Laya](https://huggingface.co/convaiinnovations/laya)
/// decision server exposing the System One wire on this machine.
///
/// Laya is an Apache-2.0 open-weights System One decision model (single
/// forward pass, calibrated choice/score/noul answers, no text generation).
/// Its `laya-serve` HTTP runtime (and the MLX conversion `laya-mlx`) exposes
/// `POST /v1/systemone` — the same wire the hosted OpenRouter System One
/// endpoint speaks — so this adapter reuses the shared transport and
/// validation machinery; only identity, default endpoint, and capability
/// facts differ.
///
/// Capability facts are honest about locality: [capabilities] reports
/// `executionLocation: local` and `networkRequirement: none` because the
/// model runs on this machine and dispatch never leaves it. The request
/// still travels over a loopback socket; "no network" here means no external
/// network egress, and local-only policy filters may safely admit it.
///
/// Auth is optional: `laya-serve` requires a `Bearer` credential only when
/// the operator configured `LAYA_API_KEY`. A supplied [apiKey] is sent as
/// that header; without one, no authorization header is sent at all.
///
/// Only `choice` questions cross this wire in v0. Laya's ordinal `score` and
/// boolean `noul` question kinds are deferred until the neutral contract
/// grows those question kinds (see the decision provider plan); they would
/// surface as typed `unsupported` outcomes, never as forced choices.
///
/// The default endpoint is the documented `laya-serve` default,
/// `http://127.0.0.1:8000/v1/systemone`. Construction is explicit and
/// performs no I/O; use [LayaServerReadinessProbe] to check server health
/// without a decision request.
final class LayaServerDecisionProvider extends SystemOneWireDecisionProvider {
  // Parameters resolve concrete defaults (endpoint, bounds, capability
  // facts) at this public boundary, so they cannot be plain super params.
  // ignore: use_super_parameters
  LayaServerDecisionProvider({
    final String? apiKey,
    final String model = 'laya',
    final Uri? endpoint,
    final http.Client? httpClient,
    final Duration timeout = const Duration(seconds: 10),
    final int maxTransientRetries = 1,
    final Duration retryDelay = const Duration(milliseconds: 50),
    final void Function(Map<String, Object?> event)? onDiagnosticEvent,
    final int maxStateUtf8Bytes = 1 << 20,
    final int maxRequestUtf8Bytes = 2 << 20,
    final int maxQuestionsPerRequest = 64,
  }) : super(
         apiKey: apiKey ?? '',
         model: model,
         endpoint: endpoint ?? Uri.parse('http://127.0.0.1:8000/v1/systemone'),
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
           executionLocation: DecisionExecutionLocation.local,
           networkRequirement: DecisionNetworkRequirement.none,
           supportsCancellation: true,
         ),
         providerId: 'laya_server',
         wireLabel: 'Laya server',
         diagnosticEventType: 'laya.server.post',
         requireAnswerConfidence: false,
         httpClient: httpClient,
         timeout: timeout,
         maxTransientRetries: maxTransientRetries,
         retryDelay: retryDelay,
         onDiagnosticEvent: onDiagnosticEvent,
         maxStateUtf8Bytes: maxStateUtf8Bytes,
         maxRequestUtf8Bytes: maxRequestUtf8Bytes,
         maxQuestionsPerRequest: maxQuestionsPerRequest,
       );

  /// Local laya-serve deployments usually run without `LAYA_API_KEY`;
  /// a missing credential is not an unready state for this adapter. When an
  /// operator did configure a key, the server's 401 surfaces as a typed
  /// authentication failure per request.
  @override
  DecisionFailure? get readinessFailure => null;

  /// Checkpoints routed by `laya-serve`'s Router (`laya`, `multilingual`,
  /// `typed-decisions`); the resolved checkpoint arrives per response and is
  /// preserved in metadata as `requestedModel`/`resolvedModel`.
  static const Set<String> knownModels = <String>{
    'laya',
    'multilingual',
    'typed-decisions',
  };
}

/// One-shot local health probe for a laya-serve endpoint.
///
/// `GET /health` never requires auth and answers without loading state, so
/// it is safe to call before constructing or dispatching through
/// [LayaServerDecisionProvider]. This is a probe, not a readiness cache:
/// providers keep reporting their local snapshot, and a failed probe must
/// not be retried blindly.
final class LayaServerReadinessProbe {
  LayaServerReadinessProbe({
    final Uri? endpoint,
    final http.Client? httpClient,
    this.timeout = const Duration(seconds: 2),
  }) : endpoint =
           endpoint ?? Uri.parse('http://127.0.0.1:8000/health'),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri endpoint;
  final Duration timeout;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<bool> ping() async {
    try {
      final response = await _httpClient
          .get(endpoint, headers: const <String, String>{'accept': 'application/json'})
          .timeout(timeout);
      return response.statusCode >= 200 && response.statusCode < 500;
    } on Object {
      return false;
    }
  }

  Future<void> dispose() async {
    if (_ownsHttpClient) _httpClient.close();
  }
}
