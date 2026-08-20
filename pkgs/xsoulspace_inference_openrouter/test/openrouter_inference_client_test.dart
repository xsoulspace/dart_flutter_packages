// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

/// Build an OpenRouter client backed by a mock HTTP handler.
OpenRouterInferenceClient _clientWithMock(
  http_testing.MockClientHandler handler, {
  String apiKey = 'test-key',
}) {
  final mock = http_testing.MockClient(handler);
  return OpenRouterInferenceClient(apiKey: apiKey, httpClient: mock);
}

/// A mock handler that returns a fixed chat-completion JSON body.
http_testing.MockClientHandler _respondWith(
  String body, {
  int statusCode = 200,
}) {
  return (request) async {
    return http.Response.bytes(
      utf8.encode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  };
}

void main() {
  group('OpenRouterInferenceClient', () {
    test('parses a text completion response', () async {
      final client = _clientWithMock(
        _respondWith('''
          {
            "choices": [
              {
                "message": {
                  "role": "assistant",
                  "content": "Hello from OpenRouter"
                }
              }
            ]
          }
          '''),
      );

      final result = await client.infer(
        InferenceRequest.structured(
          prompt: 'Say hello',
          systemPrompt: 'You are helpful.',
          task: InferenceTask.text,
        ),
      );

      expect(result.success, isTrue);
      expect(result.data, isNotNull);
      expect(result.data!.output['text'], 'Hello from OpenRouter');
      expect(result.data!.rawOutput, 'Hello from OpenRouter');
    });

    test('parses native tool calls into structured toolCalls', () async {
      final client = _clientWithMock(
        _respondWith('''
          {
            "choices": [
              {
                "message": {
                  "role": "assistant",
                  "content": null,
                  "tool_calls": [
                    {
                      "id": "call_1",
                      "type": "function",
                      "function": {
                        "name": "get_weather",
                        "arguments": "{\\"city\\": \\"Paris\\"}"
                      }
                    }
                  ]
                }
              }
            ]
          }
          '''),
      );

      final result = await client.infer(
        InferenceRequest.structured(
          prompt: 'Get the weather in Paris',
          task: InferenceTask.text,
        ),
      );

      expect(result.success, isTrue);
      expect(result.data, isNotNull);
      // The tool call must be structured — no tag round-trip.
      expect(result.data!.toolCalls, isNotEmpty);
      expect(result.data!.toolCalls.first.name, 'get_weather');
      expect(result.data!.toolCalls.first.arguments, {'city': 'Paris'});
      // rawOutput stays the raw content (no tags).
      expect(result.data!.rawOutput, isNot(contains('<call|')));
    });

    test('sends tools in the request body', () async {
      http.Request? captured;
      final client = _clientWithMock((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            '{"choices": [{"message": {"role": "assistant", "content": "ok"}}]}',
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final registry = ToolRegistry();
      registry.register(
        ToolDef.structured(
          name: ToolName('get_weather'),
          description: 'Get weather',
          parameters: SchemaBundle.empty,
          execute: (args) async => 'sunny',
        ),
      );

      final result = await client.infer(
        InferenceRequest.structured(
          prompt: 'weather',
          task: InferenceTask.text,
        ),
        toolRegistry: registry,
      );

      expect(result.success, isTrue);
      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], 'openai/gpt-4o-mini');
      expect(body['tools'], isNotNull);
      final tools = body['tools'] as List;
      expect(tools.length, 1);
      final fn =
          (tools.first as Map<String, dynamic>)['function']
              as Map<String, dynamic>;
      expect(fn['name'], 'get_weather');
    });

    test('fails without an API key', () async {
      final client = _clientWithMock(_respondWith('{}'), apiKey: '');
      final result = await client.infer(
        InferenceRequest.structured(prompt: 'hello', task: InferenceTask.text),
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'auth_failed');
    });
  });
}
