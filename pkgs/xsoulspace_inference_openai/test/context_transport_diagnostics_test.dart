import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';

import 'support.dart';

String _completed({bool usage = true}) =>
    'data: ${jsonEncode({
      'type': 'response.completed',
      'response': {
        'id': 'resp_qualified',
        'model': 'gpt-6-luna',
        'service_tier': 'default',
        'status': 'completed',
        if (usage) 'usage': {
            'input_tokens': 2000,
            'output_tokens': 1,
            'input_tokens_details': {'cached_tokens': 0},
          },
        'prompt_cache_diagnostics': {'type': 'cache_miss', 'reason': 'tools_changed', 'comparison_reusable_tokens': 1234, 'cache_missed_tokens': 1234, 'source': 'do-not-capture'},
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'OK'},
            ],
          },
        ],
      },
    })}\n\n';

Future<OpenAiResponsesClient> _client(
  http.Client transport, {
  ContextTransportDiagnosticCapture? capture,
  void Function(ResponsesDecisionReceipt)? observe,
  String model = 'gpt-6-luna',
}) async {
  final store = MemoryCredentials();
  await store.write(account());
  final client = OpenAiResponsesClient(
    auth: ChatGptAuth(store: store),
    clientId: 'oaiapp_test',
    model: model,
    client: transport,
    diagnosticCapture: capture,
    observeDecision: observe,
  );
  addTearDown(client.close);
  addTearDown(client.auth.close);
  return client;
}

InferenceRequest _request({bool explicit = false}) =>
    ResponsesInput([
      {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': 'stable 😀 source'},
          {'type': 'input_text', 'text': 'volatile suffix'},
        ],
      },
    ]).attach(
      InferenceRequest(
        prompt: '',
        systemPrompt: 'Reply exactly OK',
        reasoningEffort: 'low',
        metadata: {
          'private_metadata': 'not-a-wire-field',
          'context_cache_intent': ContextCacheIntent(
            writeAfterSegmentIds: explicit ? ['input[0].content[0]'] : [],
            lookupAfterSegmentIds: explicit ? ['input[0].content[0]'] : [],
          ).toJson(),
        },
      ),
    );

void main() {
  test(
    'provider comparison asks for diagnostics without cache mode or key',
    () async {
      final client = await _client(
        MockClient((_) async => http.Response(_completed(), 200)),
      );
      final body = client.encodeRequest(
        InferenceRequest(
          prompt: 'Reply exactly OK',
          reasoningEffort: 'low',
          metadata: {
            contextCacheComparisonMetadataKey: ContextCacheComparisonRequest(
              baselineResponseId: 'resp_test',
            ).toJson(),
          },
        ),
      );
      expect(body['prompt_cache_options'], {
        'comparison_response_id': 'resp_test',
      });
      expect(body.containsKey('prompt_cache_key'), false);
      expect(jsonEncode(body), isNot(contains('prompt_cache_breakpoint')));
    },
  );

  test(
    'HTTP diagnostics retain only allowed enums and existing request paths',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      final receipts = <ResponsesDecisionReceipt>[];
      var index = 0;
      final client = await _client(
        MockClient((_) async {
          final attempt = index++;
          return http.Response(
            jsonEncode({
              'error': {
                'code': attempt == 1 ? 'private-code' : 'unsupported_parameter',
                'type': attempt == 1 ? 'private-type' : 'invalid_request_error',
                'param': attempt == 1
                    ? 'input[0].content[0].unrequested'
                    : 'input[0].content[0].prompt_cache_breakpoint',
                'message': "Unknown parameter: 'input[0].content[0].prompt_cache_breakpoint'. private-message Bearer private-credential",
              },
            }),
            attempt == 2 ? 401 : 400,
          );
        }),
        capture: ContextTransportDiagnosticCapture(observer: events.add),
        observe: receipts.add,
      );
      for (var i = 0; i < 3; i++) {
        final result = await client.infer(_request(explicit: true));
        expect(result.success, false);
      }
      final settled = events
          .where((e) => e.stage == ContextTransportDiagnosticStage.settled)
          .toList();
      expect(settled[0].httpStatus, 400);
      expect(
        settled[0].transport['endpoint'],
        'https://api.openai.com/v1/responses',
      );
      expect(settled[0].transport['followRedirects'], false);
      expect(
        (settled[0].transport['requestControls']
            as Map)['body.prompt_cache_key'],
        {'state': 'absent'},
      );
      expect(
        settled[0].transport['clientCohort'],
        settled[1].transport['clientCohort'],
      );

      expect(settled[0].providerErrorCode, 'unsupported_parameter');
      expect(settled[0].providerErrorType, 'invalid_request_error');
      expect(
        settled[0].providerErrorMessageHint['categories'],
        contains('unknown_parameter'),
      );
      expect(
        settled[0].providerErrorMessageHint['mentionedParameters'],
        contains('prompt_cache_breakpoint'),
      );
      expect(
        settled[0].providerErrorParam,
        'input[0].content[0].prompt_cache_breakpoint',
      );
      expect(
        settled[0].outcome,
        'responses_http_failed_400_unsupported_parameter_other',
      );
      expect(settled[1].providerErrorCode, isNull);
      expect(settled[1].providerErrorType, isNull);
      expect(settled[1].providerErrorParam, isNull);
      expect(settled[1].providerErrorFieldPresence, {
        'code': true,
        'type': true,
        'param': true,
      });
      expect(settled[2].httpStatus, 401);
      expect(settled[2].providerErrorFieldPresence, isEmpty);
      expect(
        jsonEncode([
          ...settled.map((e) => e.toJson()),
          ...receipts.map((e) => e.toJson()),
        ]),
        isNot(contains('private-')),
      );
    },
  );

  test(
    'neutral alias preserves wire and implicit endpoints exclude assistant',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      final client = await _client(
        MockClient((_) async => http.Response(_completed(), 200)),
        capture: ContextTransportDiagnosticCapture(observer: events.add),
      );
      final actual =
          ResponsesInput([
            {
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': 'stable'},
              ],
            },
          ]).attach(
            InferenceRequest(
              prompt: 'volatile',
              metadata: {
                'context_cache_intent': ContextCacheIntent(
                  writeAfterSegmentIds: ['input[0].content[0]'],
                  lookupAfterSegmentIds: ['input[0].content[0]'],
                ).toJson(),
              },
            ),
          );
      final alias = actual.copyWith(
        metadata: {
          ...actual.metadata,
          'context_cache_intent': ContextCacheIntent(
            writeAfterSegmentIds: ['context[0].content[0]'],
            lookupAfterSegmentIds: ['context[0].content[0]'],
          ).toJson(),
        },
      );
      expect(client.encodeRequest(alias), client.encodeRequest(actual));
      expect(
        ((client.encodeRequest(alias)['input'] as List).first as Map)['role'],
        'user',
      );
      expect(
        ((((client.encodeRequest(alias)['input'] as List).first
                        as Map)['content']
                    as List)
                .first
            as Map)['text'],
        'stable',
      );
      expect((await client.infer(alias)).success, true);
      expect(
        events.first.snapshot.writeEndpoints.map((e) => e.afterSegmentId),
        contains('input[0].content[0]'),
      );
      events.clear();
      final grouped =
          ResponsesInput([
            {'type': 'message', 'role': 'user', 'content': 'user'},
            {
              'type': 'function_call',
              'call_id': 'a',
              'name': 'tool',
              'arguments': '{}',
            },
            {
              'type': 'function_call',
              'call_id': 'b',
              'name': 'tool',
              'arguments': '{}',
            },
            {'type': 'function_call_output', 'call_id': 'a', 'output': 'first'},
            {'type': 'function_call_output', 'call_id': 'b', 'output': 'last'},
            {'type': 'message', 'role': 'assistant', 'content': 'assistant'},
          ]).attach(
            InferenceRequest(prompt: '', systemPrompt: 'initial instructions'),
          );
      expect((await client.infer(grouped)).success, true);
      expect(
        events.first.snapshot.writeEndpoints.map((e) => e.afterSegmentId),
        ['input[4]'],
      );
      final lookup = events.first.snapshot.lookupEndpoints.map(
        (e) => e.afterSegmentId,
      );
      expect(lookup, containsAll(['instructions', 'input[0]', 'input[4]']));
      expect(lookup, isNot(contains('input[3]')));
      expect(lookup, isNot(contains('input[5]')));
      expect(
        events.first.snapshot.lookupEndpoints.every(
          (e) => e.support == ContextCacheSupport.unknown,
        ),
        true,
      );
    },
  );

  test(
    'explicit marker preserves roles/text and default leaves wire unchanged',
    () async {
      final client = await _client(
        MockClient((_) async => http.Response(_completed(), 200)),
      );
      final original = _request();
      final baseline = client.encodeRequest(original);
      final marked = client.encodeRequest(_request(explicit: true));
      final part = ((marked['input'] as List).single as Map)['content'] as List;
      expect((part.first as Map)['prompt_cache_breakpoint'], {
        'mode': 'explicit',
      });
      expect(part.last, {'type': 'input_text', 'text': 'volatile suffix'});
      (part.first as Map).remove('prompt_cache_breakpoint');
      expect(marked, baseline);
      expect(client.encodeRequest(original), baseline);
      expect(baseline.containsKey('prompt_cache_options'), false);
      expect(baseline.containsKey('max_output_tokens'), false);
    },
  );

  test(
    'exact opt-in body precedes HTTP and settled presence keeps zero distinct',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      final receipts = <ResponsesDecisionReceipt>[];
      String? sent;
      final client = await _client(
        MockClient((request) async {
          expect(events.single.stage, ContextTransportDiagnosticStage.request);
          sent = request.body;
          return http.Response(_completed(), 200);
        }),
        capture: ContextTransportDiagnosticCapture(
          includeEncodedBody: true,
          observer: events.add,
        ),
        observe: receipts.add,
      );
      expect((await client.infer(_request(explicit: true))).success, true);
      expect(events.first.exactEncodedBody, sent);
      expect(
        events.first.exactEncodedBody,
        isNot(contains('not-a-wire-field')),
      );
      final settled = events.last;
      expect(settled.stage, ContextTransportDiagnosticStage.settled);
      expect(settled.exactEncodedBody, isNull);
      expect(settled.usageReported, true);
      expect(settled.numericUsage['cached_tokens'], 0);
      expect(settled.numericUsage.containsKey('cache_write_tokens'), false);
      expect(settled.responseId, 'resp_qualified');
      expect(settled.model, 'gpt-6-luna');
      expect(settled.serviceTier, 'default');
      final receipt = receipts.single.toJson();
      expect(
        (receipt['usageFieldPresence']
            as Map)['input_tokens_details.cached_tokens'],
        true,
      );
      expect(
        (receipt['usageFieldPresence']
            as Map)['input_tokens_details.cache_write_tokens'],
        false,
      );
      expect(receipt['contextDiagnostic'], isA<Map>());
      expect(receipt['promptCacheDiagnostics'], {
        'type': 'cache_miss',
        'reason': 'tools_changed',
        'comparison_reusable_tokens': 1234,
        'cache_missed_tokens': 1234,
      });
      expect(jsonEncode(receipt), isNot(contains('do-not-capture')));
    },
  );

  test('default capture omits source and absent usage stays absent', () async {
    final events = <ContextTransportDiagnosticEvent>[];
    final client = await _client(
      MockClient((_) async => http.Response(_completed(usage: false), 200)),
      capture: ContextTransportDiagnosticCapture(observer: events.add),
    );
    expect((await client.infer(_request())).success, true);
    expect(events.every((e) => e.exactEncodedBody == null), true);
    expect(
      jsonEncode(events.map((e) => e.toJson()).toList()),
      isNot(contains('stable 😀 source')),
    );
    expect(events.last.usageReported, false);
    expect(events.last.numericUsage, isEmpty);
  });

  test(
    'encrypted continuation excludes exact body even when capture opts in',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      final client = await _client(
        MockClient((_) async => http.Response(_completed(), 200)),
        capture: ContextTransportDiagnosticCapture(
          includeEncodedBody: true,
          observer: events.add,
        ),
      );
      final request = ResponsesInput([
        {'type': 'reasoning', 'encrypted_content': 'private-ciphertext'},
      ]).attach(InferenceRequest(prompt: 'hello'));
      expect((await client.infer(request)).success, true);
      expect(events.first.exactEncodedBody, isNull);
      expect(events.first.snapshot.exactWire, false);
      expect(
        jsonEncode(events.map((e) => e.toJson()).toList()),
        isNot(contains('private-ciphertext')),
      );
    },
  );

  test('unsupported cache intent refuses before dispatch and observers cannot fail inference', () async {
    var calls = 0;
    final client = await _client(
      MockClient((_) async {
        calls++;
        return http.Response(_completed(), 200);
      }),
      model: 'unknown-model',
    );
    expect(
      (await client.infer(_request(explicit: true))).error?.code,
      'cache_breakpoint_unsupported',
    );
    expect(calls, 0);
    final observed = await _client(
      MockClient((_) async => http.Response(_completed(), 200)),
      capture: ContextTransportDiagnosticCapture(
        observer: (_) => throw StateError('observer'),
      ),
    );
    expect((await observed.infer(_request())).success, true);
  });
}
