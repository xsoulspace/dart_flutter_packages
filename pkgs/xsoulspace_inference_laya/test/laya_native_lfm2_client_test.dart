import 'dart:convert';
import 'dart:io';

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
}
