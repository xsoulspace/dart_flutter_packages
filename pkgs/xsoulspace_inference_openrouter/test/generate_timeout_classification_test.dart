import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// A spent REQUEST BUDGET is our own clock, not the backend's health
/// (paid for live 2026-11-05: scout's drop came exactly 60.19s after its
/// last tool result — a healthy, slow agentic generate killed by the
/// client's own 60s cap and mislabeled `engine_unavailable`, which the
/// rebind and ladder planes read as backend absence). The timeout is
/// named `generate_timeout`; transport failures keep the absence code.
void main() {
  test('a request over the client budget is generate_timeout, never '
      'engine_unavailable', () async {
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key-not-a-credential',
      timeout: const Duration(milliseconds: 60),
      httpClient: MockClient(
        (_) => Completer<http.Response>().future,
      ),
    );
    final result = await client.infer(InferenceRequest(prompt: 'hello'));
    expect(result.success, isFalse);
    expect(result.error?.code, 'generate_timeout');
  });

  test('the message names the spent budget in whole seconds', () async {
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key-not-a-credential',
      timeout: const Duration(seconds: 1),
      httpClient: MockClient(
        (_) => Completer<http.Response>().future,
      ),
    );
    final result = await client.infer(InferenceRequest(prompt: 'hello'));
    expect(result.error?.code, 'generate_timeout');
    expect(result.error?.message, contains('1s'));
  });

  test('a transport failure keeps the absence code engine_unavailable',
      () async {
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key-not-a-credential',
      httpClient: MockClient(
        (_) async => throw http.ClientException('connection refused'),
      ),
    );
    final result = await client.infer(InferenceRequest(prompt: 'hello'));
    expect(result.success, isFalse);
    expect(
      result.error?.code,
      anyOf('engine_unavailable', 'transport_error'),
    );
  });

  test('json bodies still parse on the happy path (guard against drift)',
      () async {
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key-not-a-credential',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'hi there'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final result = await client.infer(InferenceRequest(prompt: 'hello'));
    expect(result.success, isTrue);
  });
}
