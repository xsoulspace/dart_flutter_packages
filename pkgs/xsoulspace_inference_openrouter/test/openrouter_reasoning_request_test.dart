// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// One inference call against a mock transport; returns the wire body.
Future<Map<String, dynamic>> _wireBody(
  InferenceRequest request, {
  String response = '{"choices":[{"message":{"content":"ok"}}]}',
}) async {
  Map<String, dynamic>? body;
  final client = OpenRouterInferenceClient(
    apiKey: 'test-key',
    httpClient: http_testing.MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(response, 200);
    }),
  );
  addTearDown(client.dispose);
  final result = await client.infer(request);
  expect(result.success, isTrue, reason: result.error?.message);
  return body!;
}

void main() {
  group('OpenRouter reasoning controls', () {
    test('the requested effort reaches the wire', () async {
      final body = await _wireBody(
        InferenceRequest(prompt: 'question', reasoningEffort: 'high'),
      );
      expect(body['reasoning_effort'], 'high');
    });

    test(
      'include_reasoning is sent only when the caller asked for it',
      () async {
        final asked = await _wireBody(
          InferenceRequest(prompt: 'question', includeReasoning: true),
        );
        expect(asked['include_reasoning'], isTrue);

        final notAsked = await _wireBody(InferenceRequest(prompt: 'question'));
        expect(notAsked.containsKey('include_reasoning'), isFalse);
      },
    );

    test('stop sequences reach the wire', () async {
      final body = await _wireBody(
        InferenceRequest(prompt: 'question', stopSequences: const ['END']),
      );
      expect(body['stop_sequences'], const ['END']);
    });

    test(
      'an explicit thinking:false drops the effort instead of faking one',
      () async {
        final body = await _wireBody(
          InferenceRequest(
            prompt: 'question',
            thinking: false,
            reasoningEffort: 'high',
          ),
        );
        expect(body.containsKey('reasoning_effort'), isFalse);
      },
    );

    test(
      'the provider reasoning trace surfaces on the response meta',
      () async {
        final result = await OpenRouterInferenceClient(
          apiKey: 'test-key',
          httpClient: http_testing.MockClient(
            (_) async => http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'role': 'assistant',
                      'content': 'the answer',
                      'reasoning': 'the trace',
                    },
                  },
                ],
              }),
              200,
            ),
          ),
        ).infer(InferenceRequest(prompt: 'question', includeReasoning: true));
        expect(result.success, isTrue);
        expect(result.data!.meta['reasoning'], 'the trace');
      },
    );

    test('the advertised efforts are OpenRouter named tiers', () {
      final client = OpenRouterInferenceClient(apiKey: 'test-key');
      addTearDown(client.dispose);
      final efforts = client.supportedReasoningEfforts;
      expect(efforts, containsAll(const ['low', 'medium', 'high']));
      expect(efforts, isNot(contains('none')));
    });
  });
}
