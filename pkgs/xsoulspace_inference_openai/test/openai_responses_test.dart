import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';
import 'support.dart';

String event(Map<String, dynamic> value) => 'data: ${jsonEncode(value)}\n\n';
Map<String, dynamic> completed({List<Map<String, dynamic>>? output}) => {
  'type': 'response.completed',
  'response': {
    'id': 'response-1',
    'status': 'completed',
    'usage': {
      'input_tokens': 2000,
      'input_tokens_details': {'cached_tokens': 1500},
      'output_tokens': 20,
    },
    'output':
        output ??
        [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'hello'},
            ],
          },
        ],
  },
};

Future<OpenAiResponsesClient> client(
  http.Client transport, {
  Duration? deadline,
  void Function(ResponsesDecisionReceipt)? observeDecision,
}) async {
  final store = MemoryCredentials();
  await store.write(account());
  return OpenAiResponsesClient(
    auth: ChatGptAuth(store: store),
    clientId: 'oaiapp_test',
    model: 'test-model',
    client: transport,
    deadline: deadline ?? const Duration(seconds: 2),
    observeDecision: observeDecision,
  );
}

void main() {
  for (final status in ['in_progress', 'incomplete']) {
    test('noncompleted item $status cannot become a tool proposal', () async {
      final tools = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'inspect',
            argsSchema: SchemaBundle.empty,
            execute: (_) async => throw StateError('provider never executes'),
          ),
        );
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            event(
              completed(
                output: [
                  {
                    'type': 'function_call',
                    'status': status,
                    'name': 'inspect',
                    'call_id': 'call-1',
                    'arguments': '{}',
                    'namespace': 'harness',
                  },
                ],
              ),
            ),
            200,
          ),
        ),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
        toolRegistry: tools,
      );
      expect(result.error!.code, 'response_item_incomplete');
      expect(result.data, isNull);
    });
  }

  test('done-only EOF cannot publish output', () async {
    final itemDone = event({
      'type': 'response.output_item.done',
      'output_index': 0,
      'item': {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': 'premature'},
        ],
      },
    });
    final provider = await client(
      MockClient(
        (_) async => http.Response('${itemDone}data: [DONE]\n\n', 200),
      ),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(prompt: 'test'),
    );
    expect(result.error!.code, 'stream_interrupted');
    expect(result.data, isNull);
  });

  test('reordered identical terminal item keys reconcile', () async {
    final provider = await client(
      MockClient(
        (_) async => http.Response(
          event({
                'type': 'response.output_item.done',
                'output_index': 0,
                'item': {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'final'},
                  ],
                },
              }) +
              event(
                completed(
                  output: [
                    {
                      'content': [
                        {'text': 'final', 'type': 'output_text'},
                      ],
                      'type': 'message',
                    },
                  ],
                ),
              ),
          200,
        ),
      ),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(prompt: 'test'),
    );
    expect(result.data!.rawOutput, 'final');
  });

  test('conflicting duplicate done items refuse', () async {
    String done(String text) => event({
      'type': 'response.output_item.done',
      'output_index': 0,
      'item': {
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': text},
        ],
      },
    });
    final provider = await client(
      MockClient(
        (_) async => http.Response(
          done('first') + done('different') + event(completed(output: [])),
          200,
        ),
      ),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(prompt: 'test'),
    );
    expect(result.error!.code, 'response_output_conflict');
  });
  test(
    'finalized streamed items reconstruct empty terminal output after completion',
    () async {
      final receipts = <ResponsesDecisionReceipt>[];
      final reasoning = <String, dynamic>{
        'type': 'reasoning',
        'encrypted_content': 'opaque-secret',
        'summary': [],
      };
      final call = <String, dynamic>{
        'type': 'function_call',
        'name': 'inspect',
        'call_id': 'call-1',
        'arguments': '{}',
        'namespace': 'harness',
      };
      final tools = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'inspect',
            argsSchema: SchemaBundle.empty,
            execute: (_) async => throw StateError('provider never executes'),
          ),
        );
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            event({
                  'type': 'response.output_item.done',
                  'output_index': 1,
                  'item': call,
                }) +
                event({
                  'type': 'response.output_item.done',
                  'output_index': 0,
                  'item': reasoning,
                }) +
                event(completed(output: [])),
            200,
          ),
        ),
        observeDecision: receipts.add,
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
        toolRegistry: tools,
      );
      expect(result.success, true);
      expect(result.data!.toolCalls.single.callId, 'call-1');
      expect(result.data!.meta['responses_output'], [reasoning, call]);
      expect(receipts.single.terminalOutputItems, 0);
      expect(receipts.single.streamedDoneItems, 2);
      expect(receipts.single.parsedToolCalls, 1);
      expect(
        jsonEncode(receipts.single.toJson()),
        isNot(contains('opaque-secret')),
      );
    },
  );

  test('item completion cannot admit output after terminal failure', () async {
    final provider = await client(
      MockClient(
        (_) async => http.Response(
          event({
                'type': 'response.output_item.done',
                'output_index': 0,
                'item': {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'premature'},
                  ],
                },
              }) +
              event({
                'type': 'response.failed',
                'response': {
                  'error': {'code': 'remote_unknown'},
                },
              }),
          200,
        ),
      ),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(prompt: 'test'),
    );
    expect(result.success, false);
    expect(result.error!.code, 'response_failed');
    expect(result.data, isNull);
  });

  for (final gap in [false, true]) {
    test('final output ${gap ? 'gap' : 'conflict'} refuses', () async {
      final item = <String, dynamic>{
        'type': 'message',
        'content': [
          {'type': 'output_text', 'text': 'streamed'},
        ],
      };
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            event({
                  'type': 'response.output_item.done',
                  'output_index': gap ? 1 : 0,
                  'item': item,
                }) +
                event(
                  completed(
                    output: gap
                        ? []
                        : [
                            {
                              'type': 'message',
                              'content': [
                                {'type': 'output_text', 'text': 'different'},
                              ],
                            },
                          ],
                  ),
                ),
            200,
          ),
        ),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
      );
      expect(
        result.error!.code,
        gap ? 'response_output_incomplete' : 'response_output_conflict',
      );
    });
  }

  test('genuinely empty terminal output has a named refusal', () async {
    final provider = await client(
      MockClient((_) async => http.Response(event(completed(output: [])), 200)),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(prompt: 'test'),
    );
    expect(result.error!.code, 'response_empty_output');
  });
  test(
    'decision receipt separates streamed text from empty terminal output',
    () async {
      final receipts = <ResponsesDecisionReceipt>[];
      final terminal = completed(
        output: [
          {
            'type': 'reasoning',
            'summary': [
              {'text': 'secret-reasoning'},
            ],
          },
        ],
      );
      final response = terminal['response'] as Map;
      response['id'] = 'secret-response-id';
      response['usage'] = {
        'input_tokens': 20,
        'output_tokens': 10,
        'total_tokens': 30,
        'input_tokens_details': {'cached_tokens': 7, 'secret': 'secret-cache'},
        'output_tokens_details': {'reasoning_tokens': 10},
        'remote_secret': 'secret-usage',
      };
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            event({
                  'type': 'response.output_text.delta',
                  'delta': 'secret-delta',
                }) +
                event(terminal),
            200,
          ),
        ),
        observeDecision: receipts.add,
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
      );
      expect(result.success, true);
      final receipt = receipts.single.toJson();
      expect(receipt['outputKinds'], {'reasoning': 1});
      expect(receipt['streamedTextChars'], 12);
      expect(receipt['wireTextChars'], 0);
      expect(receipt['parsedTextChars'], 0);
      expect(receipt['parsedToolCalls'], 0);
      expect(receipt['usage'], {
        'input_tokens': 20,
        'output_tokens': 10,
        'total_tokens': 30,
        'cached_tokens': 7,
        'reasoning_tokens': 10,
      });
      expect(jsonEncode(receipt), isNot(contains('secret')));
    },
  );

  test(
    'decision observation counts native calls without exposing arguments',
    () async {
      final receipts = <ResponsesDecisionReceipt>[];
      final tools = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'inspect',
            argsSchema: SchemaBundle.empty,
            execute: (_) async => throw StateError('not provider-owned'),
          ),
        );
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            event(
              completed(
                output: [
                  {
                    'type': 'function_call',
                    'name': 'inspect',
                    'call_id': 'secret-call',
                    'arguments': '{"value":"secret-argument"}',
                    'namespace': 'harness',
                  },
                ],
              ),
            ),
            200,
          ),
        ),
        observeDecision: receipts.add,
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
        toolRegistry: tools,
      );
      expect(result.data!.toolCalls, hasLength(1));
      final receipt = receipts.single.toJson();
      expect(receipt['advertisedTools'], 1);
      expect(receipt['outputKinds'], {'function_call': 1});
      expect(receipt['parsedToolCalls'], 1);
      expect(jsonEncode(receipt), isNot(contains('secret')));
    },
  );

  test(
    'throwing observer cannot change inference or physical settlement',
    () async {
      final provider = await client(
        MockClient((_) async => http.Response(event(completed()), 200)),
        observeDecision: (_) => throw StateError('observer failed'),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(
        InferenceRequest.structured(prompt: 'test'),
      );
      expect(result.success, true);
      expect(result.data!.rawOutput, 'hello');
      await provider.settleActive();
    },
  );
  test('unresolved bundle references refuse before network dispatch', () async {
    var dispatched = false;
    final provider = await client(
      MockClient((_) async {
        dispatched = true;
        return http.Response('', 200);
      }),
    );
    addTearDown(provider.close);
    addTearDown(provider.auth.close);
    final result = await provider.infer(
      InferenceRequest.structured(
        prompt: 'inspect',
        outputSchema: const SchemaBundle(root: ReferenceSchema('unresolved')),
      ),
    );
    expect(result.error!.code, 'schema_unsupported');
    expect(dispatched, false);
  });
  test(
    'core bundles convert to wire schemas and retain host validation',
    () async {
      const schema = SchemaBundle(
        root: ObjectSchema(
          name: 'decision',
          properties: [
            SchemaProperty(
              name: 'required',
              schema: PrimitiveSchema(type: PrimitiveType.string),
            ),
            SchemaProperty(
              name: 'optional',
              schema: PrimitiveSchema(type: PrimitiveType.string),
              isOptional: true,
            ),
          ],
        ),
      );
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'inspect',
            argsSchema: schema,
            execute: (_) async =>
                throw StateError('provider must not execute tools'),
          ),
        );
      var calls = 0;
      final provider = await client(
        MockClient((wire) async {
          final body = jsonDecode(wire.body) as Map;
          final function = body['tools'].single['tools'].single;
          final format = body['text']['format'];
          for (final converted in [function['parameters'], format['schema']]) {
            expect(converted['type'], 'object');
            expect(converted.containsKey('root'), false);
            expect(converted['required'], ['required']);
            expect(
              converted['properties'].keys,
              containsAll(['required', 'optional']),
            );
          }
          expect(function['strict'], false);
          expect(format['strict'], false);
          return http.Response(
            event(
              completed(
                output: [
                  {
                    'type': 'message',
                    'role': 'assistant',
                    'content': [
                      {
                        'type': 'output_text',
                        'text': ++calls == 1
                            ? '{"required":"ok"}'
                            : '{"optional":"missing-required"}',
                      },
                    ],
                  },
                ],
              ),
            ),
            200,
          );
        }),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final request = InferenceRequest.structured(
        prompt: 'inspect',
        outputSchema: schema,
      );
      final valid = await provider.infer(request, toolRegistry: registry);
      expect(valid.success, true);
      expect(valid.data!.structuredOutput, {'required': 'ok'});
      final invalid = await provider.infer(request, toolRegistry: registry);
      expect(invalid.success, false);
      expect(invalid.error!.code, 'invalid_structured_output');
    },
  );
  test(
    'HTTP refusals retain status without exposing remote response bodies',
    () async {
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            '{"error":{"message":"secret-token-and-document-content"}}',
            400,
          ),
        ),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(InferenceRequest(prompt: 'inspect'));
      expect(result.success, false);
      expect(result.error!.code, 'responses_http_failed_400');
      expect(result.error!.message, isNot(contains('secret')));
    },
  );
  test(
    'HTTP schema diagnostics expose only fixed categories and families',
    () async {
      final provider = await client(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'invalid_json_schema',
                'param': 'text.format.schema.secret-token',
                'message': 'private-source-and-secret-token',
              },
            }),
            400,
          ),
        ),
      );
      addTearDown(provider.close);
      addTearDown(provider.auth.close);
      final result = await provider.infer(InferenceRequest(prompt: 'inspect'));
      expect(
        result.error!.code,
        'responses_http_failed_400_invalid_json_schema_text',
      );
      expect(result.error!.message, isNot(contains('secret')));
    },
  );
  test('catalog cancellation settles without cancelling shared auth', () async {
    final entered = Completer<void>();
    final provider = await client(
      CatalogAbortClient((request) async {
        entered.complete();
        await request.abortTrigger;
        throw http.RequestAbortedException(request.url);
      }),
    );
    final pending = provider.listModels();
    final failure = expectLater(
      pending,
      throwsA(
        isA<ChatGptAuthException>().having(
          (e) => e.code,
          'code',
          'model_catalog_cancelled',
        ),
      ),
    );
    await entered.future;
    provider.cancelActive();
    await failure;
    await provider.settleActive();
    expect(
      (await provider.auth.accountForInference('oaiapp_test')).subject,
      'subject',
    );
    provider.close();
    provider.auth.close();
  });

  test(
    'continuation preserves current cut and rejects unsupported roles/items',
    () async {
      final provider = await client(
        MockClient((_) async => http.Response('', 200)),
      );
      final current =
          ResponsesInput([
            {'type': 'message', 'role': 'assistant', 'content': 'recent'},
          ]).attach(
            InferenceRequest(
              prompt: 'next',
              contextFragments: ['mandatory obligation'],
            ),
          );
      final input = provider.encodeRequest(current)['input'] as List;
      expect(input.first['content'], 'mandatory obligation');
      expect(input[1]['content'], 'recent');
      for (final item in [
        {'type': 'message', 'role': 'developer', 'content': 'override'},
        {'type': 'custom_tool_call', 'call_id': 'unsupported'},
        {'type': 'item_reference', 'id': 'not-stored'},
      ]) {
        final result = await provider.infer(
          ResponsesInput([item]).attach(InferenceRequest(prompt: 'next')),
        );
        expect(result.success, false);
      }
    },
  );

  test('unsupported actionable output cannot silently succeed', () async {
    final provider = await client(
      MockClient(
        (_) async => http.Response(
          event(
            completed(
              output: [
                {'type': 'custom_tool_call', 'call_id': 'unsupported'},
              ],
            ),
          ),
          200,
        ),
      ),
    );
    expect(
      (await provider.infer(InferenceRequest(prompt: 'next'))).error!.code,
      'response_item_unsupported',
    );
  });

  test(
    'fragmented UTF8 and SSE retain exact text and typed namespace identity',
    () async {
      final output = [
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'héllo'},
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'one',
          'namespace': 'harness',
          'name': 'inspect',
          'arguments': '{}',
        },
        {
          'type': 'function_call',
          'call_id': 'two',
          'namespace': 'harness',
          'name': 'inspect',
          'arguments': '{}',
        },
      ];
      final wire = utf8.encode(event(completed(output: output)));
      final provider = await client(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.fromIterable(wire.map((byte) => [byte])),
            200,
          ),
        ),
      );
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'fixture',
            execute: (_) async => null,
          ),
        );
      final result = await provider.infer(
        InferenceRequest(prompt: 'next'),
        toolRegistry: registry,
      );
      expect(result.success, true);
      expect(result.data!.rawOutput, 'héllo');
      expect(result.data!.toolCalls.map((call) => call.callId), ['one', 'two']);
      expect(result.data!.toolCalls.map((call) => call.namespace), [
        'harness',
        'harness',
      ]);
    },
  );
  test('orphaned or unfinished tool pairs refuse before transport', () async {
    var calls = 0;
    final provider = await client(
      MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    for (final items in [
      [ResponsesInput.toolOutput('orphan', 'output')],
      [
        {
          'type': 'function_call',
          'call_id': 'unfinished',
          'name': 'inspect',
          'arguments': '{}',
        },
      ],
    ]) {
      final request = ResponsesInput(
        items,
      ).attach(InferenceRequest(prompt: 'continue'));
      expect(
        (await provider.infer(request)).error!.code,
        'tool_pair_incomplete',
      );
    }
    expect(calls, 0);
  });
  test(
    'native wire uses public endpoint, stateless SSE and mapped instructions',
    () async {
      final provider = await client(
        MockClient((request) async {
          expect(request.url.toString(), 'https://api.openai.com/v1/responses');
          expect(request.headers['Authorization'], 'Bearer test-access');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['store'], false);
          expect(body['stream'], true);
          expect(body['instructions'], 'stable');
          expect(body.containsKey('metadata'), false);
          expect(body.containsKey('previous_response_id'), false);
          return http.Response(event(completed()), 200);
        }),
      );
      final result = await provider.infer(
        InferenceRequest(prompt: 'question', systemPrompt: 'stable'),
      );
      expect(result.success, true);
      expect(result.data!.rawOutput, 'hello');
      expect((result.data!.meta['usage'] as Map)['input_tokens_details'], {
        'cached_tokens': 1500,
      });
    },
  );

  test(
    'tool calls preserve correlated output without executing model actions',
    () async {
      var executions = 0;
      final registry = ToolRegistry()
        ..register(
          ToolDef(
            name: const ToolName('inspect'),
            description: 'inspect',
            execute: (_) async {
              executions++;
              return 'done';
            },
          ),
        );
      final nativeOutput = [
        {
          'type': 'function_call',
          'id': 'item-1',
          'call_id': 'call-1',
          'name': 'inspect',
          'arguments': '{"path":"a.dart"}',
        },
      ];
      final provider = await client(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect((body['tools'] as List).single['type'], 'namespace');
          final function = (body['tools'] as List).single['tools'].single;
          expect(function['strict'], false);
          return http.Response(event(completed(output: nativeOutput)), 200);
        }),
      );
      final result = await provider.infer(
        InferenceRequest(prompt: 'inspect'),
        toolRegistry: registry,
      );
      expect(result.success, true);
      expect(executions, 0);
      expect(result.data!.toolCalls.single.arguments['path'], 'a.dart');
      final next = ResponsesInput([
        ...nativeOutput,
        ResponsesInput.toolOutput('call-1', 'observed'),
      ]).attach(InferenceRequest(prompt: 'continue'));
      final input = provider.encodeRequest(next)['input'] as List;
      expect(input[0]['call_id'], input[1]['call_id']);
    },
  );

  test('late subscription failure defeats already streamed text', () async {
    final provider = await client(
      MockClient(
        (_) async => http.Response(
          event({
                'type': 'response.output_text.delta',
                'delta': 'looks successful',
              }) +
              event({
                'type': 'response.failed',
                'response': {
                  'error': {
                    'code': 'subscription_sharing_usage_limit_exceeded',
                    'message': 'private detail',
                  },
                },
              }),
          200,
        ),
      ),
    );
    final session = await provider.streamStructuredText(
      InferenceRequest(prompt: 'question'),
    );
    final events = session.events.toList();
    final result = await session.result;
    expect(result.success, false);
    expect(result.error!.code, 'subscription_usage_limit_exceeded');
    expect(result.error!.message, isNot(contains('private detail')));
    expect((await events).any((e) => e.textDelta == 'looks successful'), true);
    await session.dispose();
  });

  test('EOF and DONE without completed are interrupted', () async {
    for (final wire in ['', 'data: [DONE]\n\n']) {
      final provider = await client(
        MockClient((_) async => http.Response(wire, 200)),
      );
      expect(
        (await provider.infer(
          InferenceRequest(prompt: 'question'),
        )).error!.code,
        'stream_interrupted',
      );
    }
  });

  test('unsupported knobs refuse before transport', () async {
    var calls = 0;
    final provider = await client(
      MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    final result = await provider.infer(
      InferenceRequest(prompt: 'question', maxTokens: 20),
    );
    expect(result.error!.code, 'generation_option_unsupported');
    expect(calls, 0);
  });

  test('invalid schema output cannot succeed', () async {
    final provider = await client(
      MockClient((_) async => http.Response(event(completed()), 200)),
    );
    final result = await provider.infer(
      InferenceRequest(
        prompt: 'question',
        outputSchema: {
          'type': 'object',
          'properties': {
            'ok': {'type': 'boolean'},
          },
          'required': ['ok'],
        },
      ),
    );
    expect(result.success, false);
    expect(result.error!.code, 'invalid_structured_output');
  });

  test(
    'catalog uses account-specific slugs and preserves server ordering',
    () async {
      final provider = await client(
        MockClient((request) async {
          expect(request.url.path, '/v1/models');
          return http.Response(
            jsonEncode({
              'models': [
                {'slug': 'b', 'display_name': 'B', 'visibility': 'list'},
                {
                  'slug': 'hidden',
                  'display_name': 'Hidden',
                  'visibility': 'hide',
                },
                {'slug': 'a', 'display_name': 'A', 'visibility': 'list'},
              ],
            }),
            200,
          );
        }),
      );
      expect((await provider.listModels()).map((m) => m.slug), ['b', 'a']);
    },
  );
}

final class CatalogAbortClient extends http.BaseClient {
  CatalogAbortClient(this.handle);
  final Future<http.StreamedResponse> Function(http.AbortableRequest) handle;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request as http.AbortableRequest);
}
