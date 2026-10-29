import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// A provider key/billing limit (402/403 with `limit_source`) is a NAMED
/// state — `provider_key_limit_exhausted` — never `auth_failed`: the
/// 2026-10-29 durable lane paid seven futile retries and a misleading
/// verdict for the conflation.
void main() {
  Future<InferenceResult<InferenceResponse>> run(int status, String body) {
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key-not-a-credential',
      httpClient: MockClient(
        (_) async => http.Response(body, status, headers: {
          'content-type': 'application/json',
        }),
      ),
    );
    return client.infer(InferenceRequest(prompt: 'hello'));
  }

  test('a 403 key-limit body is named provider_key_limit_exhausted',
      () async {
    final result = await run(
      403,
      jsonEncode({
        'error': {
          'message': 'Key limit exceeded (total limit).',
          'code': 403,
          'metadata': {'limit_source': 'openrouter_key_limit'},
        },
      }),
    );
    expect(result.success, isFalse);
    expect(result.error?.code, 'provider_key_limit_exhausted');
  });

  test('a 402 key-limit body is named provider_key_limit_exhausted',
      () async {
    final result = await run(
      402,
      jsonEncode({
        'error': {
          'message': 'Key limit exceeded (total limit).',
          'metadata': {'limit_source': 'openrouter_key_limit'},
        },
      }),
    );
    expect(result.error?.code, 'provider_key_limit_exhausted');
  });

  test('a plain 403 without a limit declaration stays auth_failed',
      () async {
    final result = await run(
      403,
      jsonEncode({
        'error': {'message': 'Forbidden', 'code': 403},
      }),
    );
    expect(result.error?.code, 'auth_failed');
  });
}
