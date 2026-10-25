// The seed law: a request that carries a seed is never silently dropped.
// The Anthropic Messages API has NO seed parameter, so the seed is NOT
// HONOURED — it is echoed on the response meta and reported as a warning.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_anthropic/xsoulspace_inference_anthropic.dart';

void main() {
  test(
    'a seeded request is echoed and refused, never silently dropped',
    () async {
      Map<String, dynamic>? sent;
      final client = AnthropicInferenceClient(
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"content":[{"type":"text","text":"hello"}]}',
            200,
          );
        }),
      );

      final result = await client.infer(
        InferenceRequest(prompt: 'hello', maxTokens: 64, seed: 7),
      );

      expect(result.success, isTrue);
      // NOT HONOURED: the Messages API has no seed field — nothing is sent.
      expect(sent!.containsKey('seed'), isFalse);
      // The seed is still visible: echoed on the meta...
      expect(result.data!.meta[inferenceSeedMetaKey], 7);
      // ...and the provider's inability to honor it is stated plainly.
      expect(result.data!.warnings, hasLength(1));
      final warning = result.data!.warnings.single;
      expect(warning, contains('no seed parameter'));
      expect(warning, contains('cannot honor'));
      expect(warning, contains('7'));
    },
  );

  test('an unseeded request leaves the seed off the meta', () async {
    final client = AnthropicInferenceClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        return http.Response(
          '{"content":[{"type":"text","text":"hello"}]}',
          200,
        );
      }),
    );

    final result = await client.infer(
      InferenceRequest(prompt: 'hello', maxTokens: 64),
    );

    expect(result.success, isTrue);
    expect(result.data!.meta.containsKey(inferenceSeedMetaKey), isFalse);
    expect(result.data!.warnings, isEmpty);
  });
}
