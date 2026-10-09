import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// R2's in-process client over the qwen FFI (ADR 0054): the engine test
/// checks greedy ids against the committed parity fixture; the wire test
/// proves the same engine behind the OpenAI-compatible chat routes
/// (`/health`, `POST /v1/chat/completions`) — the wire `mlx_lm.server`
/// speaks, with no Python and no spawned process.
///
/// Skips honestly when the dylib or the cached snapshot is absent.
void main() {
  final fixtureFile = File(
    'native/laya_rust/testdata/qwen3_06b_parity.json',
  );
  final snapshotDir = resolveQwenSnapshotDir(null);

  test('engine reproduces the fixture greedy ids in-process', () async {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('parity fixture absent');
    }
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final prompt = fixture['prompt'] as String;
    final wantPromptIds = <int>[
      for (final v in fixture['prompt_ids'] as List) v as int,
    ];
    final wantGreedy = <int>[
      for (final v in fixture['greedy_ids'] as List) v as int,
    ];

    final completion = engine.generate(prompt: prompt, maxTokens: 8);
    expect(completion.promptIds, wantPromptIds,
        reason: 'Dart-side prompt tokenization diverged');
    expect(
      completion.ids.sublist(wantPromptIds.length),
      wantGreedy.sublist(0, 8),
      reason: 'in-process greedy ids diverge from the reference',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('generateAsync returns the fixture prefix off the calling isolate', () async {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('parity fixture absent');
    }
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final prompt = fixture['prompt'] as String;
    final wantGreedy = <int>[
      for (final v in fixture['greedy_ids'] as List) v as int,
    ];

    final completion = await engine.generateAsync(prompt: prompt, maxTokens: 8);
    expect(
      completion.ids.sublist(completion.promptIds.length),
      wantGreedy.sublist(0, 8),
      reason: 'async greedy ids diverge from the reference',
    );
    expect(completion.text, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('wire: chat completions over the in-process engine', () async {
    if (snapshotDir == null) {
      return markTestSkipped('Qwen3-0.6B-4bit snapshot absent');
    }
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    final server = LayaQwenChatServer(engine: engine);
    await server.start();
    addTearDown(server.stop);

    final health = await http.get(Uri.parse('${server.url}/health'));
    expect(health.statusCode, 200);
    expect(jsonDecode(health.body)['status'], 'ok');
    expect(jsonDecode(health.body)['engine'], 'laya-native-qwen');

    final completion = await http.post(
      Uri.parse('${server.url}/v1/chat/completions'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(<String, Object?>{
        'model': 'qwen3-0.6b-4bit',
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': 'Say hello.'},
        ],
        'max_tokens': 8,
      }),
    );
    expect(completion.statusCode, 200);
    final body = jsonDecode(completion.body) as Map<String, dynamic>;
    final choices = body['choices'] as List;
    expect(choices, isNotEmpty);
    final message = (choices.first as Map)['message'] as Map;
    expect(message['role'], 'assistant');
    expect((message['content'] as String).isNotEmpty, isTrue,
        reason: 'wire completion returned empty content');
    final usage = body['usage'] as Map;
    expect(usage['prompt_tokens'], greaterThan(0));
    expect(usage['completion_tokens'], 8);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
