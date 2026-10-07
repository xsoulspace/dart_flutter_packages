import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_anthropic/xsoulspace_inference_anthropic.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  group('AnthropicInferenceClient', () {
    test('is unavailable without an API key and fails before dispatch', () async {
      var requests = 0;
      final client = AnthropicInferenceClient(
        httpClient: MockClient((_) async {
          requests++;
          return _messageResponse();
        }),
      );

      expect(client.isAvailable, isFalse);
      expect(await client.refreshAvailability(), isFalse);
      final result = await client.infer(_request(maxTokens: 128));
      expect(result.success, isFalse);
      expect(result.error?.code, 'auth_failed');
      expect(requests, 0);
    });

    test('rejects requests without an explicit token budget', () async {
      var requests = 0;
      final client = _client(
        MockClient((_) async {
          requests++;
          return _messageResponse();
        }),
      );

      final result = await client.infer(
        _request(),
      ); // no maxTokens on purpose

      expect(result.success, isFalse);
      expect(result.error?.code, 'missing_max_tokens');
      expect(requests, 0);
    });

    test('rejects unsupported tasks before dispatch', () async {
      var requests = 0;
      final client = _client(
        MockClient((_) async {
          requests++;
          return _messageResponse();
        }),
      );

      final result = await client.infer(
        InferenceRequest.speechToText(
          audioInput: const InferenceAudioInput.bytes(
            bytes: <int>[1],
            mimeType: 'audio/wav',
          ),
          metadata: <String, dynamic>{'model': 'claude-sonnet-4-5'},
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, errorCodeTaskUnsupported);
      expect(requests, 0);
    });

    test('sends the Messages wire with required headers and budget',
        () async {
      late http.Request captured;
      final client = _client(
        MockClient((final request) async {
          captured = request;
          return _messageResponse();
        }),
      );

      final result = await client.infer(
        _request(
          maxTokens: 512,
          temperature: 0.3,
          stopSequences: <String>['END'],
          systemPrompt: 'Be terse.',
        ),
      );

      expect(result.success, isTrue);
      expect(captured.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(captured.headers['x-api-key'], 'test-key');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-sonnet-4-5');
      expect(body['max_tokens'], 512);
      expect(body['system'], 'Be terse.');
      expect(body['temperature'], 0.3);
      expect(body['stop_sequences'], <String>['END']);
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
      expect(
        (messages.single as Map<String, dynamic>)['role'],
        'user',
      );
    });

    test('parses text content and passes through usage and stop reason',
        () async {
      final client = _client(MockClient((_) async => _messageResponse()));

      final result = await client.infer(_request(maxTokens: 128));

      expect(result.success, isTrue);
      final response = result.data!;
      expect(response.rawOutput, 'A terse answer.');
      expect(response.structuredOutput['text'], 'A terse answer.');
      expect(response.meta['stop_reason'], 'end_turn');
      expect(
        (response.meta['usage'] as Map<String, dynamic>)['input_tokens'],
        12,
      );
    });

    test('structured task spells the schema into the system prompt and '
        'parses the JSON reply', () async {
      late http.Request captured;
      final client = _client(
        MockClient((final request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'content': <Map<String, dynamic>>[
                {'type': 'text', 'text': '{"answer": 42}'},
              ],
              'stop_reason': 'end_turn',
              'usage': <String, dynamic>{'input_tokens': 10, 'output_tokens': 5},
            }),
            200,
          );
        }),
      );

      final result = await client.infer(
        InferenceRequest.structured(
          prompt: 'extract the answer',
          task: InferenceTask.nativelyStructuredText,
          outputSchema: SchemaBundle(
            root: FM.object(
              'Answer',
              properties: () => <SchemaProperty>[
                FM.prop('answer', FM.integer()),
              ],
            ),
          ),
          maxTokens: 256,
          metadata: <String, dynamic>{'model': 'claude-sonnet-4-5'},
        ),
      );

      expect(result.success, isTrue);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final system = body['system'] as String;
      expect(system, contains('"answer"'));
      expect(system, contains('ONLY a valid JSON object'));
      expect((result.data!).structuredOutput, <String, dynamic>{
        'answer': 42,
      });
    });

    test('maps registered tools to input_schema and parses tool_use blocks',
        () async {
      late http.Request captured;
      final client = _client(
        MockClient((final request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'content': <Map<String, dynamic>>[
                {
                  'type': 'tool_use',
                  'id': 'toolu_1',
                  'name': 'read_file',
                  'input': <String, dynamic>{'path': 'lib/main.dart'},
                },
              ],
              'stop_reason': 'tool_use',
              'usage': <String, dynamic>{'input_tokens': 20, 'output_tokens': 8},
            }),
            200,
          );
        }),
      );
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('read_file'),
            description: 'Read a file from the workspace',
            argsSchema: SchemaBundle(
              root: FM.object(
                'ReadFileArgs',
                properties: () => <SchemaProperty>[
                  FM.prop('path', FM.string()),
                ],
              ),
            ),
            execute: (_) async => null,
          ),
        );

      final result = await client.infer(
        _request(maxTokens: 256),
        toolRegistry: registry,
      );

      expect(result.success, isTrue);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final tools = body['tools'] as List<dynamic>;
      final tool = tools.single as Map<String, dynamic>;
      expect(tool['name'], 'read_file');
      expect(tool['input_schema'], isA<Map<String, dynamic>>());
      expect(tool.containsKey('parameters'), isFalse);

      final response = result.data!;
      expect(response.toolCalls, hasLength(1));
      expect(response.toolCalls.single.name.value, 'read_file');
      expect(response.toolCalls.single.arguments['path'], 'lib/main.dart');
      expect(response.meta['stop_reason'], 'tool_use');
    });

    test('renders assistant fragments as multi-turn messages', () async {
      late http.Request captured;
      final client = _client(
        MockClient((final request) async {
          captured = request;
          return _messageResponse();
        }),
      );

      await client.infer(
        _request(
          maxTokens: 64,
          contextFragments: <Object>[
            'asst:Earlier I proposed applying the edit.',
            'stray context note',
          ],
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(3));
      expect(
        (messages[0] as Map<String, dynamic>)['role'],
        'user',
        reason: 'projected context renders before the assistant turn',
      );
      expect(
        (messages[1] as Map<String, dynamic>)['role'],
        'assistant',
      );
      expect(
        (messages[1] as Map<String, dynamic>)['content'],
        'Earlier I proposed applying the edit.',
      );
      expect((messages[2] as Map<String, dynamic>)['content'], _prompt);
    });

    test('extracts the API error message and maps status codes', () async {
      final unauthorized = _client(
        MockClient(
          (_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'type': 'error',
              'error': <String, dynamic>{
                'type': 'authentication_error',
                'message': 'invalid x-api-key',
              },
            }),
            401,
          ),
        ),
      );
      final overloaded = _client(
        MockClient((_) async => http.Response('{"type":"error"}', 529)),
      );

      final authResult = await unauthorized.infer(_request(maxTokens: 64));
      final overloadedResult = await overloaded.infer(_request(maxTokens: 64));

      expect(authResult.error?.code, 'auth_failed');
      expect(authResult.error?.message, 'invalid x-api-key');
      expect(overloadedResult.error?.code, 'engine_unavailable');
    });

    test('times out into a typed engine_unavailable failure', () async {
      final client = _client(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return _messageResponse();
        }),
        timeout: const Duration(milliseconds: 20),
      );

      final result = await client.infer(_request(maxTokens: 64));

      expect(result.success, isFalse);
      expect(result.error?.code, 'engine_unavailable');
    });

    test('diagnostic observer sees the exact POST without credentials',
        () async {
      final events = <Map<String, Object?>>[];
      final client = AnthropicInferenceClient(
        apiKey: 'test-key',
        httpClient: MockClient((_) async => _messageResponse()),
        onTransportDiagnostic: events.add,
      );

      await client.infer(_request(maxTokens: 64));

      expect(events, hasLength(1));
      expect(events.single['type'], 'anthropic.messages.post');
      expect(events.single.toString(), isNot(contains('test-key')));
    });
  });
}

const String _prompt = 'Summarize the failing test.';

AnthropicInferenceClient _client(
  final http.Client client, {
  final Duration timeout = const Duration(seconds: 1),
}) => AnthropicInferenceClient(
  apiKey: 'test-key',
  httpClient: client,
  timeout: timeout,
);

InferenceRequest _request({
  final int? maxTokens,
  final double? temperature,
  final List<String> stopSequences = const <String>[],
  final String systemPrompt = '',
  final List<Object> contextFragments = const <Object>[],
}) => InferenceRequest(
  prompt: _prompt,
  maxTokens: maxTokens,
  temperature: temperature,
  stopSequences: stopSequences,
  systemPrompt: systemPrompt,
  contextFragments: contextFragments,
  metadata: <String, dynamic>{'model': 'claude-sonnet-4-5'},
);

http.Response _messageResponse() => http.Response(
  jsonEncode(<String, dynamic>{
    'id': 'msg_1',
    'type': 'message',
    'role': 'assistant',
    'model': 'claude-sonnet-4-5',
    'content': <Map<String, dynamic>>[
      {'type': 'text', 'text': 'A terse answer.'},
    ],
    'stop_reason': 'end_turn',
    'usage': <String, dynamic>{'input_tokens': 12, 'output_tokens': 4},
  }),
  200,
);
