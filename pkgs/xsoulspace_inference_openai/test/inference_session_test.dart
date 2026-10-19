import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openai/xsoulspace_inference_openai.dart';

import 'support.dart';

http.Response response([String? token]) => http.Response(
  'data: ${jsonEncode({
    'type': 'response.completed',
    'response': {
      'status': 'completed',
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
  })}\n\n',
  200,
  headers: {'x-codex-turn-state': ?token},
);
InferenceRequest request({
  String session = 'actor',
  String turn = 'turn-1',
  String group = 'group',
  bool headers = true,
}) => OpenAiSessionOptions(sessionAffinity: headers, turnAffinity: headers)
    .attach(
      InferenceSessionSpec(
        id: session,
        affinityKey: 'affinity',
        cache: InferenceCachePolicy(group: group),
      ).attach(
        InferenceRequest(prompt: 'exact input', reasoningEffort: 'low'),
        turn: InferenceTurnSpec(id: turn),
      ),
    );

void main() {
  late ChatGptAuth auth;
  late OpenAiSessionState state;
  setUp(() async {
    final store = MemoryCredentials();
    await store.write(account());
    auth = ChatGptAuth(store: store);
    state = OpenAiSessionState();
  });
  tearDown(() => auth.close());
  OpenAiResponsesClient client(
    http.Client transport, {
    String model = 'gpt-6-luna',
    ChatGptAuth? owner,
  }) {
    final value = OpenAiResponsesClient(
      auth: owner ?? auth,
      clientId: 'oaiapp_test',
      model: model,
      client: transport,
      sessionState: state,
    );
    addTearDown(value.close);
    return value;
  }

  test(
    'cache key is declarative; headers are opt-in; turn token resets',
    () async {
      final wires = <http.Request>[];
      var i = 0;
      final c = client(
        MockClient((r) async {
          wires.add(r);
          return response('token-${i++}');
        }),
      );
      for (final r in [
        InferenceRequest(prompt: 'plain'),
        request(headers: false),
        request(),
        request(),
        request(turn: 'turn-2'),
        request(turn: 'turn-2', group: 'new-group'),
      ]) {
        expect((await c.infer(r)).success, true);
      }
      expect(jsonDecode(wires[0].body).containsKey('prompt_cache_key'), false);
      expect(wires[0].headers.containsKey('session-id'), false);
      expect(jsonDecode(wires[1].body)['prompt_cache_key'], 'group');
      expect(wires[1].headers.containsKey('session-id'), false);
      expect(wires[2].headers['session-id'], 'affinity');
      expect(wires[2].headers['thread-id'], 'actor');
      expect(wires[2].headers['x-codex-turn-state'], isNull);
      expect(wires[3].headers['x-codex-turn-state'], 'token-2');
      expect(wires[4].headers['x-codex-turn-state'], isNull);
      expect(wires[5].headers['x-codex-turn-state'], isNull);
      expect(
        wires.every(
          (r) => r.url.toString() == 'https://api.openai.com/v1/responses',
        ),
        true,
      );
    },
  );
  test(
    'shared state survives client release but resets on model or auth owner',
    () async {
      final tokens = <String?>[];
      final wire = MockClient((r) async {
        tokens.add(r.headers['x-codex-turn-state']);
        return response('server-token');
      });
      final first = client(wire);
      await first.infer(request());
      first.close();
      await client(wire).infer(request());
      await client(wire, model: 'gpt-6-sol').infer(request());
      final store = MemoryCredentials();
      await store.write(account());
      final other = ChatGptAuth(store: store);
      addTearDown(other.close);
      await client(wire, model: 'gpt-6-sol', owner: other).infer(request());
      expect(tokens, [null, 'server-token', null, null]);
      state.clear();
      await client(wire).infer(request());
      expect(tokens.last, isNull);
    },
  );
  test('late old-turn response cannot replace new-turn routing', () async {
    final started = Completer<void>();
    final finish = Completer<http.Response>();
    final tokens = <String?>[];
    var count = 0;
    final c = client(
      MockClient((r) async {
        tokens.add(r.headers['x-codex-turn-state']);
        if (count++ == 0) {
          started.complete();
          return finish.future;
        }
        return response('new-turn-token');
      }),
    );
    final old = c.infer(request());
    await started.future;
    await c.infer(request(turn: 'next'));
    finish.complete(response('old-turn-token'));
    await old;
    await c.infer(request(turn: 'next'));
    expect(tokens, [null, null, 'new-turn-token']);
  });
  test(
    'malformed session options and missing turn refuse before dispatch',
    () async {
      var count = 0;
      final c = client(
        MockClient((_) async {
          count++;
          return response();
        }),
      );
      final invalid =
          const OpenAiSessionOptions(
            sessionAffinity: true,
            turnAffinity: true,
          ).attach(
            InferenceSessionSpec(id: 's').attach(InferenceRequest(prompt: 'x')),
          );
      expect((await c.infer(invalid)).success, false);
      expect(
        (await c.infer(
          const OpenAiSessionOptions().attach(InferenceRequest(prompt: 'x')),
        )).success,
        false,
      );
      expect(count, 0);
    },
  );
}
