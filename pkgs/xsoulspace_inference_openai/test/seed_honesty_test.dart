// The seed law: a request that carries a seed is never silently dropped.
// OpenAI's Responses API has a top-level integer `seed`, so the seed is
// HONOURED — it reaches the wire and the response meta records it.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';

import 'support.dart';

String _completedEvent() =>
    'data: ${jsonEncode({
      'type': 'response.completed',
      'response': {
        'id': 'response-1',
        'status': 'completed',
        'usage': {'input_tokens': 10, 'output_tokens': 2},
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'hello'},
            ],
          },
        ],
      },
    })}\n\n';

void main() {
  test('a seeded request puts the seed on the wire and on the meta', () async {
    Map<String, dynamic>? sent;
    final store = MemoryCredentials();
    await store.write(account());
    final provider = OpenAiResponsesClient(
      auth: ChatGptAuth(store: store),
      clientId: 'oaiapp_test',
      model: 'test-model',
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(_completedEvent(), 200);
      }),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);

    final result = await provider.infer(
      InferenceRequest(prompt: 'question', seed: 7),
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
      final store = MemoryCredentials();
      await store.write(account());
      final provider = OpenAiResponsesClient(
        auth: ChatGptAuth(store: store),
        clientId: 'oaiapp_test',
        model: 'test-model',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(_completedEvent(), 200);
        }),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);

      final result = await provider.infer(InferenceRequest(prompt: 'question'));

      expect(result.success, isTrue);
      expect(sent!.containsKey('seed'), isFalse);
      expect(result.data!.meta.containsKey(inferenceSeedMetaKey), isFalse);
    },
  );
}
