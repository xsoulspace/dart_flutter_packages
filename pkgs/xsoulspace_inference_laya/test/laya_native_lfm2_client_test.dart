import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

/// The LFM2 rung's in-process client over the lfm2 FFI (ADR 0055): the
/// engine test checks greedy ids against the committed parity fixture —
/// through text→tokenize→generate→decode, the whole FFI surface.
///
/// Skips honestly when the dylib or the cached snapshot is absent.
void main() {
  final fixtureFile = File('native/laya_rust/testdata/lfm25_12b_parity.json');
  final snapshotDir = resolveLfm2SnapshotDir(null);

  test('engine reproduces the fixture greedy ids in-process', () async {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('parity fixture absent');
    }
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
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
        reason: 'native tokenize+BOS diverged from the reference ids');
    expect(
      completion.ids.sublist(wantPromptIds.length),
      wantGreedy.sublist(0, 8),
      reason: 'in-process greedy ids diverge from the reference',
    );
    expect(completion.text, isNotEmpty,
        reason: 'decoded text must not be empty');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('explicit promptIds ride verbatim (no BOS injected)', () async {
    if (snapshotDir == null) {
      return markTestSkipped('LFM2.5-1.2B snapshot absent');
    }
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    const rawIds = <int>[27388, 958, 1620];
    final completion = engine.generate(promptIds: rawIds, maxTokens: 4);
    expect(
      completion.promptIds,
      rawIds,
      reason: 'explicit prompt_ids must not gain a BOS',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('opt-in EOS stop breaks at the fixture eos; default keeps running', () async {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('parity fixture absent');
    }
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    final fixture =
        jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    final prompt = fixture['prompt'] as String;
    final wantGreedy = <int>[
      for (final v in fixture['greedy_ids'] as List) v as int,
    ];
    final eosPos = wantGreedy.indexWhere((id) => id == 7 || id == 2);
    expect(eosPos, greaterThan(0), reason: 'fixture must contain an eos');

    // Default OFF: the stream runs past the eos (the fixture gate above).
    final plain = engine.generate(prompt: prompt, maxTokens: eosPos + 3);
    expect(
      plain.ids.length - plain.promptIds.length,
      eosPos + 3,
      reason: 'without stopOnEos generation must run past the eos',
    );

    // Opt-in: emit the first eos itself, then stop (HF convention).
    final stopped = engine.generate(
      prompt: prompt,
      maxTokens: wantGreedy.length,
      stopOnEos: true,
      eosIds: const <int>[7, 2],
    );
    final generated = stopped.ids.sublist(stopped.promptIds.length);
    expect(generated.length, eosPos + 1);
    expect(generated, wantGreedy.sublist(0, eosPos + 1),
        reason: 'stopped stream must equal the fixture prefix through the eos');
    expect(generated.last, wantGreedy[eosPos],
        reason: 'the eos token itself must be emitted');
    expect(stopped.text.endsWith('<|im_end|>'), isTrue,
        reason: 'the added-token literal must decode into the text tail');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('generateAsync returns the fixture prefix off the calling isolate', () async {
    if (!fixtureFile.existsSync()) {
      return markTestSkipped('parity fixture absent');
    }
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
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

  test('wire: chat completions render the template and stop at im_end', () async {
    if (snapshotDir == null) {
      return markTestSkipped('LFM2.5-1.2B snapshot absent');
    }
    final NativeLfm2TextEngine engine;
    try {
      engine = await NativeLfm2TextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native lfm2 engine unavailable: $error');
    }
    addTearDown(engine.dispose);

    const maxTokens = 48;
    final server = LayaLfm2ChatServer(engine: engine);
    await server.start();
    addTearDown(server.stop);

    final health = await http.get(Uri.parse('${server.url}/health'));
    expect(health.statusCode, 200);
    expect(jsonDecode(health.body)['status'], 'ok');
    expect(jsonDecode(health.body)['engine'], 'laya-native-lfm2');

    final completion = await http.post(
      Uri.parse('${server.url}/v1/chat/completions'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(<String, Object?>{
        'model': 'lfm2.5-1.2b-instruct-mlx-4bit',
        'messages': <Object?>[
          <String, Object?>{
            'role': 'system',
            'content': 'Answer in one short sentence.',
          },
          <String, Object?>{'role': 'user', 'content': 'Say hello.'},
        ],
        'max_tokens': maxTokens,
      }),
    );
    expect(completion.statusCode, 200);
    final body = jsonDecode(completion.body) as Map<String, dynamic>;
    final choices = body['choices'] as List;
    expect(choices, isNotEmpty);
    final message = (choices.first as Map)['message'] as Map;
    expect(message['role'], 'assistant');
    final content = message['content'] as String;
    expect(content.isNotEmpty, isTrue,
        reason: 'wire completion returned empty content');
    final usage = body['usage'] as Map;
    expect(usage['prompt_tokens'], greaterThan(0));
    expect(usage['completion_tokens'], greaterThanOrEqualTo(1));
    expect(usage['completion_tokens'], lessThanOrEqualTo(maxTokens));
    if ((usage['completion_tokens'] as int) < maxTokens) {
      // Generation ended before the cap — the only way the opt-in stop
      // allows that is the EOS break, so the emitted eos literal must
      // terminate the decoded text.
      expect(content.endsWith('<|im_end|>'), isTrue,
          reason: 'early wire completion must end at the im_end stop');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
