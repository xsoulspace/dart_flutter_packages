import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

String _response({bool usage = true}) => jsonEncode({
  'id': 'gen_test',
  'model': 'anthropic/claude-test',
  'service_tier': 'default',
  'choices': [
    {
      'message': {'content': 'OK'},
    },
  ],
  if (usage)
    'usage': {
      'prompt_tokens': 2000,
      'completion_tokens': 1,
      'prompt_tokens_details': {'cached_tokens': 0},
    },
});

void main() {
  test(
    'shared declarations map affinity and accounting independently',
    () async {
      final wires = <Map<String, dynamic>>[];
      final client = OpenRouterInferenceClient(
        apiKey: 'test-only',
        httpClient: MockClient((request) async {
          wires.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(_response(), 200);
        }),
      );
      addTearDown(client.dispose);
      final plain = InferenceRequest(prompt: 'exact input');
      final spec = InferenceSessionSpec(
        id: 'actor-thread',
        affinityKey: 'routing-group',
        cache: InferenceCachePolicy(group: 'authorized-prefix'),
      );
      for (final request in [
        plain,
        spec.attach(plain),
        spec.attach(plain, turn: InferenceTurnSpec(id: 'next')),
      ]) {
        expect((await client.infer(request)).success, true);
      }
      expect(wires[0].containsKey('session_id'), false);
      expect(wires[1]['session_id'], 'routing-group');
      expect(wires[1]['prompt_cache_key'], 'authorized-prefix');
      expect(wires[1]['messages'], wires[0]['messages']);
      expect(wires[1], wires[2]);
      expect(wires[1].containsKey('inference_session'), false);
      expect(jsonEncode(wires[1]), isNot(contains('x-codex-turn-state')));
    },
  );

  test('unqualified provider comparison refuses before dispatch', () async {
    var sent = false;
    final client = OpenRouterInferenceClient(
      apiKey: 'test-only',
      httpClient: MockClient((_) async {
        sent = true;
        return http.Response(_response(), 200);
      }),
    );
    addTearDown(client.dispose);
    final result = await client.infer(
      InferenceRequest(
        prompt: 'OK',
        metadata: {
          contextCacheComparisonMetadataKey: ContextCacheComparisonRequest(
            baselineResponseId: 'resp_test',
          ).toJson(),
        },
      ),
    );
    expect(result.success, false);
    expect(result.error?.code, 'cache_comparison_unsupported');
    expect(sent, false);
  });

  test(
    'HTTP diagnostics preserve safe code/type/path without remote messages',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      var index = 0;
      final client = OpenRouterInferenceClient(
        apiKey: 'test-only',
        diagnosticCapture: ContextTransportDiagnosticCapture(
          observer: events.add,
        ),
        httpClient: MockClient((_) async {
          final attempt = index++;
          return http.Response(
            jsonEncode({
              'error': {
                'code': attempt == 1 ? 'private-code' : 400,
                'type': attempt == 1 ? 'private-type' : 'invalid_request_error',
                'param': attempt == 1
                    ? 'messages[0].unrequested'
                    : 'messages[0].content',
                'message': 'private-message Bearer private-credential',
              },
            }),
            attempt == 2 ? 429 : 400,
          );
        }),
      );
      addTearDown(client.dispose);
      for (var i = 0; i < 3; i++) {
        expect(
          (await client.infer(InferenceRequest(prompt: 'hello'))).success,
          false,
        );
      }
      final settled = events
          .where((e) => e.stage == ContextTransportDiagnosticStage.settled)
          .toList();
      expect(settled[0].httpStatus, 400);
      expect(
        settled[0].transport['endpoint'],
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(
        (settled[0].transport['requestControls']
            as Map)['body.prompt_cache_key'],
        {'state': 'absent'},
      );
      expect(
        settled[0].transport['clientCohort'],
        settled[1].transport['clientCohort'],
      );

      expect(settled[0].providerErrorCode, '400');
      expect(settled[0].providerErrorType, 'invalid_request_error');
      expect(settled[0].providerErrorParam, 'messages[0].content');
      expect(settled[1].providerErrorCode, isNull);
      expect(settled[1].providerErrorType, isNull);
      expect(settled[1].providerErrorParam, isNull);
      expect(settled[1].providerErrorFieldPresence, {
        'code': true,
        'type': true,
        'param': true,
      });
      expect(settled[2].httpStatus, 429);
      expect(settled[2].providerErrorFieldPresence, isEmpty);
      expect(
        jsonEncode(settled.map((e) => e.toJson()).toList()),
        isNot(contains('private-')),
      );
    },
  );

  test(
    'same neutral content alias preserves actual-path wire and role',
    () async {
      final sent = <Map>[];
      final events = <ContextTransportDiagnosticEvent>[];
      final client = OpenRouterInferenceClient(
        apiKey: 'test-only',
        defaultModel: 'anthropic/claude-test',
        cacheBreakpointPolicy:
            OpenRouterCacheBreakpointPolicy.anthropicEphemeral,
        diagnosticCapture: ContextTransportDiagnosticCapture(
          observer: events.add,
        ),
        httpClient: MockClient((request) async {
          sent.add(jsonDecode(request.body) as Map);
          return http.Response(_response(), 200);
        }),
      );
      addTearDown(client.dispose);
      for (final id in ['messages[0].content[0]', 'context[0].content[0]']) {
        expect(
          (await client.infer(
            InferenceRequest(
              prompt: 'volatile',
              contextFragments: ['stable'],
              metadata: {
                'context_cache_intent': ContextCacheIntent(
                  writeAfterSegmentIds: [id],
                  lookupAfterSegmentIds: [id],
                ).toJson(),
              },
            ),
          )).success,
          true,
        );
      }
      expect(sent[0], sent[1]);
      expect((sent[1]['messages'] as List).first, {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text':
                'Projected context (green-screened; anything not shown is off-screen):\n'
                'stable',
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      });
      expect(
        events[2].snapshot.writeEndpoints.single.afterSegmentId,
        'messages[0].content[0]',
      );
    },
  );

  test(
    'default wire observer coexists with source-free generic diagnostics',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      final legacy = <Map<String, Object?>>[];
      String? sent;
      final client = OpenRouterInferenceClient(
        apiKey: 'test-only',
        httpClient: MockClient((request) async {
          sent = request.body;
          return http.Response(_response(), 200);
        }),
        onTransportDiagnostic: legacy.add,
        diagnosticCapture: ContextTransportDiagnosticCapture(
          observer: events.add,
        ),
      );
      addTearDown(client.dispose);
      final result = await client.infer(
        InferenceRequest(
          prompt: 'private source',
          maxTokens: 2,
          temperature: 0,
        ),
      );
      expect(result.success, true);
      expect(legacy.single['body'], sent);
      final wire = jsonDecode(sent!) as Map;
      expect(wire['max_tokens'], 2);
      expect(wire['temperature'], 0);
      expect(jsonEncode(wire), isNot(contains('cache_control')));
      expect(events.every((e) => e.exactEncodedBody == null), true);
      expect(
        jsonEncode(events.map((e) => e.toJson()).toList()),
        isNot(contains('private source')),
      );
      expect(events.last.numericUsage['cached_tokens'], 0);
      expect(events.last.usageReported, true);
      expect(events.last.responseId, 'gen_test');
      expect(events.last.model, 'anthropic/claude-test');
      expect(events.last.snapshot.writeEndpoints, isEmpty);
    },
  );

  test('unknown breakpoint route refuses before dispatch', () async {
    var calls = 0;
    final client = OpenRouterInferenceClient(
      apiKey: 'test-only',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response(_response(), 200);
      }),
    );
    addTearDown(client.dispose);
    final result = await client.infer(
      InferenceRequest(
        prompt: 'stable',
        metadata: {
          'context_cache_intent': ContextCacheIntent(
            writeAfterSegmentIds: ['messages[0]'],
          ).toJson(),
        },
      ),
    );
    expect(result.error?.code, 'cache_breakpoint_support_unknown');
    expect(calls, 0);
  });

  test(
    'explicit qualified dialect maps only selected block and exact body',
    () async {
      final events = <ContextTransportDiagnosticEvent>[];
      String? sent;
      final client = OpenRouterInferenceClient(
        apiKey: 'test-only',
        defaultModel: 'anthropic/claude-test',
        cacheBreakpointPolicy:
            OpenRouterCacheBreakpointPolicy.anthropicEphemeral,
        diagnosticCapture: ContextTransportDiagnosticCapture(
          includeEncodedBody: true,
          observer: events.add,
        ),
        httpClient: MockClient((request) async {
          sent = request.body;
          return http.Response(_response(usage: false), 200);
        }),
      );
      addTearDown(client.dispose);
      final result = await client.infer(
        InferenceRequest(
          prompt: 'volatile',
          systemPrompt: 'stable',
          metadata: {
            'context_cache_intent': ContextCacheIntent(
              writeAfterSegmentIds: ['messages[0]'],
              lookupAfterSegmentIds: ['messages[0]'],
            ).toJson(),
          },
        ),
      );
      expect(result.success, true);
      final messages = (jsonDecode(sent!) as Map)['messages'] as List;
      expect(messages.first, {
        'role': 'system',
        'content': [
          {
            'type': 'text',
            'text': 'stable',
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      });
      expect(messages.last, {'role': 'user', 'content': 'volatile'});
      expect(events.first.exactEncodedBody, sent);
      expect(events.last.usageReported, false);
      expect(events.last.numericUsage, isEmpty);
      expect(
        events.first.snapshot.writeEndpoints.single.support,
        ContextCacheSupport.known,
      );
    },
  );
}
