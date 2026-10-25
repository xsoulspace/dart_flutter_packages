// The seed law: a request that carries a seed is never silently dropped.
// OpenRouter's chat completions API is OpenAI-compatible and accepts the
// top-level integer `seed`, so the seed is HONOURED — it reaches the wire
// and the response meta records it.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

void main() {
  test('a seeded request puts the seed on the wire and on the meta', () async {
    Map<String, dynamic>? sent;
    final client = OpenRouterInferenceClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"role":"assistant","content":"ok"}}]}',
          200,
        );
      }),
    );

    final result = await client.infer(
      InferenceRequest(prompt: 'hello', seed: 7),
    );

    expect(result.success, isTrue);
    // HONOURED: the seed is mapped to the wire...
    expect(sent!['seed'], 7);
    // ...and echoed on the response meta, with no refusal warning.
    expect(result.data!.meta[inferenceSeedMetaKey], 7);
    expect(result.data!.warnings, isEmpty);
  });

  test(
    'an unseeded request leaves the seed off the wire and the meta',
    () async {
      Map<String, dynamic>? sent;
      final client = OpenRouterInferenceClient(
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"choices":[{"message":{"role":"assistant","content":"ok"}}]}',
            200,
          );
        }),
      );

      final result = await client.infer(InferenceRequest(prompt: 'hello'));

      expect(result.success, isTrue);
      expect(sent!.containsKey('seed'), isFalse);
      expect(result.data!.meta.containsKey(inferenceSeedMetaKey), isFalse);
    },
  );
}
