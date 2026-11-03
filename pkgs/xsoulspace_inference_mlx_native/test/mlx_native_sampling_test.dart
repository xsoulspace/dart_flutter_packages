import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

void main() {
  // The opt-in sampling rung (solo generate): temperature + HF/CTRL
  // repetition penalty over prompt+generated tokens. Absent fields stay
  // byte-identical greedy (the parity fixtures pin that natively); these
  // tests pin the DART-side contract: the probe, the pass-through, the
  // honesty warning only when the dylib lacks the ABI, and that sampled
  // answers are clean text. Skips honestly without the dylib/snapshots.
  test('sampling ABI probe answers on this dylib', () {
    // The probe must not throw whether or not the dylib is new.
    expect(
      NativeQwenTextEngine.samplingApiSupported,
      isA<bool>(),
    );
    expect(NativeLfm2TextEngine.samplingApiSupported, isA<bool>());
  });

  test('qwen: sampled chat answers cleanly; no honesty warning when honored',
      () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadQwen();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(client.dispose);

    final result = await client.infer(
      InferenceRequest(
        prompt: 'Reply with exactly one word: 2+2=?',
        maxTokens: 24,
        temperature: 0.7,
        repetitionPenalty: 1.1,
      ),
    );
    expect(result.success, isTrue, reason: '${result.error?.toJson()}');
    expect(result.data!.rawOutput, isNotEmpty);
    expect(result.data!.rawOutput!.endsWith('<|im_end|>'), isFalse);
    if (NativeQwenTextEngine.samplingApiSupported) {
      expect(
        result.warnings.where((w) => w.contains('greedily')),
        isEmpty,
        reason: 'a sampling-capable dylib must not claim greedy decode',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('qwen: temperature 0 + penalty-only request stays greedy and answers',
      () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadQwen();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(client.dispose);

    final penaltyOnly = await client.infer(
      InferenceRequest(
        prompt: 'Reply with exactly one word: the sky color by day?',
        maxTokens: 16,
        temperature: 0.0,
        repetitionPenalty: 1.3,
      ),
    );
    expect(penaltyOnly.success, isTrue, reason: '${penaltyOnly.error?.toJson()}');
    expect(penaltyOnly.data!.rawOutput, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('qwen: request without sampling fields stays byte-identical old shape',
      () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadQwen();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(client.dispose);

    final greedy = await client.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2),
    );
    expect(greedy.success, isTrue);
    expect(greedy.warnings, isEmpty);
    expect(greedy.data!.rawOutput, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('cached Qwen3 variants name themselves from a hub cache', () async {
    final temp = await Directory.systemTemp.createTemp('hub_scan_');
    addTearDown(() => temp.delete(recursive: true));
    for (final name in [
      'models--mlx-community--Qwen3-0.6B-4bit',
      'models--mlx-community--Qwen3-1.7B-4bit',
      'models--mlx-community--Qwen3-0.6B-bf16',
      'models--mlx-community--NotQwen-7B',
    ]) {
      final snap = Directory('${temp.path}/$name/snapshots/abc123');
      snap.createSync(recursive: true);
      File('${snap.path}/config.json').writeAsStringSync('{}');
    }
    final variants = listCachedQwen3Snapshots(hubRoot: temp.path);
    expect(
      variants.map((v) => v.refName),
      ['qwen3-0.6b', 'qwen3-0.6b-bf16', 'qwen3-1.7b'],
      reason: 'sorted by name; non-Qwen3 dirs ignored',
    );
    expect(variants.last.paramLabel, '1.7B');

    // A named variant resolves to its snapshot dir; unknown names refuse.
    final dir = resolveQwen3SnapshotVariant('qwen3-1.7b', hubRoot: temp.path);
    expect(dir, contains('Qwen3-1.7B-4bit'));
    expect(
      resolveQwen3SnapshotVariant('qwen3-not-there', hubRoot: temp.path),
      isNull,
    );
    expect(resolveQwen3SnapshotVariant('', hubRoot: temp.path), isNull);
  });

  test('invalid sampling params refuse at the FFI boundary', () async {
    final MlxNativeTextClient client;
    try {
      client = await MlxNativeTextClient.loadQwen();
    } on Object catch (error) {
      return markTestSkipped('native qwen engine unavailable: $error');
    }
    addTearDown(client.dispose);
    if (!NativeQwenTextEngine.samplingApiSupported) {
      return markTestSkipped('dylib predates the sampling ABI');
    }

    final result = await client.infer(
      InferenceRequest(prompt: 'x', maxTokens: 2, repetitionPenalty: 0.5),
    );
    expect(result.success, isFalse);
    expect(result.error!.code, 'native_engine');
    expect(result.error!.message, contains('repetition_penalty'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
