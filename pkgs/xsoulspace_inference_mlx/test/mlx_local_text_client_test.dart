import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx/xsoulspace_inference_mlx.dart';

void main() {
  group('MlxServeRuntime', () {
    test('attach mode: health miss names the server honestly', () async {
      final runtime = MlxServeRuntime(
        httpClient: MockClient(
          (_) async => throw StateError('connection refused'),
        ),
      );
      expect(await runtime.ensureRunning(), isFalse);
      expect(runtime.status.$1, LocalServeState.unavailable);
      expect(runtime.status.$2, contains('no mlx-lm server answering'));
      expect(runtime.healthEndpoint.port, MlxServeRuntime.defaultPort);
      await runtime.dispose();
    });

    test(
      'attach mode: ready server flips readiness without spawning',
      () async {
        final runtime = MlxServeRuntime(
          httpClient: MockClient((_) async => http.Response('ok', 200)),
          processStarter: (_, _, _) async => throw StateError('no spawn'),
        );
        expect(await runtime.ensureRunning(), isTrue);
        expect(runtime.isReady, isTrue);
        await runtime.dispose();
      },
    );

    test('serve arguments bind the model to the loopback port', () {
      expect(
        MlxServeArguments.command(model: 'org/model-4bit', port: 9000),
        <String>[
          '--model',
          'org/model-4bit',
          '--host',
          '127.0.0.1',
          '--port',
          '9000',
        ],
      );
    });
  });

  group('MlxLocalTextClient', () {
    test(
      'detached runtime infers as typed unavailable, no wire traffic',
      () async {
        var posts = 0;
        final client = _client(
          httpClient: MockClient((_) async {
            posts++;
            return http.Response('{}', 200);
          }),
        );

        expect(client.id, 'mlx_local');
        expect(client.isAvailable, isFalse);
        expect(client.supportedTasks, <InferenceTask>{InferenceTask.text});

        final result = await client.infer(_textRequest('compress this'));
        expect(result.success, isFalse);
        expect(result.error!.code, 'unavailable');
        expect(posts, 0);
        await client.dispose();
      },
    );

    test('non-text tasks are refused without touching the wire', () async {
      final client = _client();
      final result = await client.infer(
        InferenceRequest(prompt: 'x', task: InferenceTask.speechToText),
      );
      expect(result.success, isFalse);
      expect(result.error!.code, 'unsupported_task');
      await client.dispose();
    });

    test('ready runtime generates over the chat wire end to end', () async {
      final engine = ScriptedMlxChatEngine(<String>[
        'kernel resume fixes; mesh gate green',
      ]);
      final server = FakeMlxChatServer(engine: engine);
      await server.start();
      final runtime = MlxServeRuntime(
        healthEndpoint: server.url.replace(path: '/health'),
        httpClient: MockClient((_) async => http.Response('ok', 200)),
      );
      final events = <Map<String, Object?>>[];
      final client = MlxLocalTextClient(
        runtime: runtime,
        endpoint: HttpMlxChatEndpoint(
          endpoint: server.url,
          model: 'fake-mlx',
          onDiagnosticEvent: events.add,
        ),
        defaultMaxTokens: 96,
        defaultTemperature: 0.0,
      );
      await runtime.ensureRunning();

      final result = await client.infer(
        InferenceRequest(
          prompt: 'material about kernel fixes',
          systemPrompt: NapDraftPrompts.summarySystem(maxBytes: 280),
          maxTokens: 96,
        ),
      );

      expect(result.success, isTrue);
      expect(result.data!.rawOutput, 'kernel resume fixes; mesh gate green');
      expect(result.data!.meta['usage'], isA<Map<dynamic, dynamic>>());
      // The request carried the system prompt and the greedy default.
      final request = engine.requests.single;
      expect(request.messages.first.role, 'system');
      expect(request.maxTokens, 96);
      expect(request.temperature, 0.0);
      // Diagnostics are content-free: no material, no completion.
      final encoded = jsonEncode(events);
      expect(encoded.contains('material about kernel'), isFalse);
      expect(encoded.contains('kernel resume fixes'), isFalse);

      await client.dispose();
      await server.stop();
    });

    test('a 500 surfaces as a retryable transport failure', () async {
      final server = FakeMlxChatServer(engine: _ThrowingEngine());
      await server.start();
      final runtime = MlxServeRuntime(
        healthEndpoint: server.url.replace(path: '/health'),
        httpClient: MockClient((_) async => http.Response('ok', 200)),
      );
      final client = MlxLocalTextClient(
        runtime: runtime,
        endpoint: HttpMlxChatEndpoint(endpoint: server.url),
      );
      await runtime.ensureRunning();

      final result = await client.infer(_textRequest('x'));
      // The scripted engine throws inside the server route: the wire
      // skeleton contains it as a 500, and the client retries once before
      // surfacing a transport failure.
      expect(result.success, isFalse);
      expect(result.error!.code, 'transport');

      await client.dispose();
      await runtime.dispose();
      await server.stop();
    });

    test('readiness names the runtime reason', () async {
      final client = _client();
      expect(client.readiness.state, InferenceReadinessState.unavailable);
      expect(client.readiness.issues.single.code, 'server_not_running');
      await client.dispose();
    });
  });

  group('ScriptedMlxChatEngine', () {
    test('replays pins in order, then sticks on the last', () {
      final engine = ScriptedMlxChatEngine(<String>['a', 'b']);
      expect(engine.answer(_chatRequest()).text, 'a');
      expect(engine.answer(_chatRequest()).text, 'b');
      expect(engine.answer(_chatRequest()).text, 'b');
      engine.reset();
      expect(engine.answer(_chatRequest()).text, 'a');
    });
  });

  group('NapDraftPrompts', () {
    test('refusal detection is exact-token', () {
      expect(NapDraftPrompts.isRefusal(' REFUSE \n'), isTrue);
      expect(NapDraftPrompts.isRefusal('REFUSE: unsure'), isFalse);
      expect(NapDraftPrompts.isRefusal('a faithful summary'), isFalse);
    });

    test('summary prompt carries the block, budget, and material', () {
      final user = NapDraftPrompts.summaryUser(
        blockLabel: '#10-25',
        maxBytes: 280,
        material: '  #10 2026-10-01 did things',
      );
      expect(user.contains('#10-25'), isTrue);
      expect(user.contains('280'), isTrue);
      expect(user.contains('#10 2026-10-01 did things'), isTrue);
      expect(
        NapDraftPrompts.summarySystem(maxBytes: 280).contains('REFUSE'),
        isTrue,
      );
    });
  });
}

MlxLocalTextClient _client({final http.Client? httpClient}) =>
    MlxLocalTextClient(
      runtime: MlxServeRuntime(
        httpClient:
            httpClient ?? MockClient((_) async => throw StateError('refused')),
      ),
      endpoint: _StaticEndpoint(),
    );

InferenceRequest _textRequest(final String prompt) =>
    InferenceRequest(prompt: prompt);

MlxChatRequest _chatRequest() => const MlxChatRequest(
  model: 'fake-mlx',
  messages: <MlxChatMessage>[MlxChatMessage(role: 'user', content: 'x')],
);

final class _ThrowingEngine implements MlxScriptedEngine {
  @override
  MlxChatResult answer(final MlxChatRequest request) =>
      throw StateError('engine bug');
}

/// Endpoint stub for tests that never reach the wire (unavailable paths).
final class _StaticEndpoint implements MlxChatEndpoint {
  @override
  Future<MlxChatResult> complete(final MlxChatRequest request) =>
      throw StateError('must not be reached');

  @override
  Future<void> dispose() async {}
}
