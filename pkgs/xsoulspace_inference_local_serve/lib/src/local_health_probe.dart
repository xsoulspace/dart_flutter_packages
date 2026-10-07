import 'package:http/http.dart' as http;

/// One-shot loopback health probe for a local model server.
///
/// `GET /health` (or the configured path) never requires auth and answers
/// without loading state, so it is safe to call before constructing or
/// dispatching through a client. This is a probe, not a readiness cache:
/// runtimes keep reporting their local snapshot, and a failed probe must
/// not be retried blindly. Any answering status below 500 counts as alive —
/// a 404 from a server without a health route still proves the socket is up.
final class LocalHealthProbe {
  LocalHealthProbe({
    required this.endpoint,
    final http.Client? httpClient,
    this.timeout = const Duration(seconds: 2),
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final Uri endpoint;
  final Duration timeout;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<bool> ping() async {
    try {
      final response = await _httpClient
          .get(
            endpoint,
            headers: const <String, String>{'accept': 'application/json'},
          )
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
