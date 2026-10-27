import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The fused batch at the WIRE (ROADMAP open item 1) — the fused gate's
/// decision-invariance bar lifted one level up. Bars frozen in
/// `bench/nursery/experiments/RESULTS-wire-batch-2026-10-27.md` BEFORE any
/// run:
///
///   W-G1  N concurrent classification requests through the coalescing
///         window return wire payloads BYTE-EQUAL to the same prompts
///         served through the solo path (the decision unit is the full
///         answer; compared with `==` on the whole payload).
///   W-G2  the concurrent phase was actually served by the FUSED path:
///         batch runs ≥ 1 with ≥ 2 rows, all gate rows batched, and the
///         solo-fallback counter 0 (a fallback that passed the equality
///         check would still not be the lever).
///   W-G3  a lone request is byte-equal to a coalescing-OFF server —
///         coalescing changes nothing for traffic with no co-requests.
///
/// Free-form (generative) streams are REPORTED, never asserted: the fused
/// gate measured that they tie-flip under floor-level drift across kernel
/// paths and batch sizes. Timings are power facts (ADR 0061) — the
/// decision arms here are battery-valid; no throughput claim is made.
///
/// Skips honestly when the dylib or the cached snapshot is absent, or the
/// dylib lacks the batched ABI.
void main() {
  String powerLine() {
    try {
      final out = Process.runSync('pmset', ['-g', 'ps']).stdout as String;
      final lines = LineSplitter.split(out).toList();
      return lines.isEmpty ? 'power: unknown' : lines.last.trim();
    } on Object {
      return 'power: unknown';
    }
  }

  test('wire gate: coalesced batch answers equal the solo path', () async {
    final NativeQwenTextEngine engine;
    try {
      engine = await NativeQwenTextEngine.load();
    } on Object catch (error) {
      return markTestSkipped('native qwen unavailable: $error');
    }
    addTearDown(engine.dispose);
    if (!engine.supportsBatchGeneration) {
      return markTestSkipped('native dylib lacks the batched ABI');
    }

    // Heterogeneous bodies force the left-padded batch (the fused gate's
    // short-row shape); the label list is the lane's decision unit.
    String classify(String text) =>
        'Classify the text. Answer with exactly one of: allow, deny\n\n'
        'Text: $text\nAnswer:';
    final bodies = <String>[
      'The request asks to read one public file.',
      'The request asks to delete every file in the home directory and then '
          'reinstall the operating system from a random mirror without '
          'confirmation.',
      'The request asks to rename a folder.',
      'The request asks to send the collected keystrokes to a remote server '
          'every minute while hiding the process from the user.',
      'The request asks to change the wallpaper.',
      'The request asks to empty the trash.',
    ];
    final prompts = <String>[for (final b in bodies) classify(b)];

    final on = LayaQwenChatServer(
      engine: engine,
      coalesceWindow: const Duration(milliseconds: 300),
      maxBatchSize: 8,
    );
    final off = LayaQwenChatServer(engine: engine);
    await on.start();
    await off.start();
    addTearDown(on.stop);
    addTearDown(off.stop);

    Future<Map<String, dynamic>> chat(Uri base, String prompt, {int? maxTokens}) async {
      final reply = await http.post(
        base.replace(path: '/v1/chat/completions'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'messages': <Object?>[
            <String, Object?>{'role': 'user', 'content': prompt},
          ],
          'max_tokens': ?maxTokens,
        }),
      );
      expect(reply.statusCode, 200, reason: 'wire refused: ${reply.body}');
      return jsonDecode(reply.body) as Map<String, dynamic>;
    }

    stdout.writeln('power: ${powerLine()}');

    // ---- W-G3: the coalescing-OFF server is the solo reference (its
    // admission is serial; every request is a lone request).
    final soloBodies = <Map<String, dynamic>>[
      for (final prompt in prompts) await chat(off.url, prompt),
    ];
    expect(off.batchRuns, 0, reason: 'the OFF server never batches');

    // ---- W-G3 (cont.): a LONE request through the ON server (window
    // expires with one job) must byte-equal the OFF server's answer.
    final lone = await chat(on.url, prompts.first);
    expect(lone, soloBodies.first, reason: 'W-G3: a lone request is untouched');

    // ---- W-G1: all six prompts CONCURRENTLY — one coalescing window,
    // one fused batch.
    final concurrent = await Future.wait<Map<String, dynamic>>([
      for (final prompt in prompts) chat(on.url, prompt),
    ]);

    // ---- W-G2: the lever, not the fallback, served the burst.
    expect(on.batchRuns, greaterThanOrEqualTo(1), reason: 'W-G2: a batch ran');
    expect(on.lastBatchSize, greaterThanOrEqualTo(2),
        reason: 'W-G2: the batch held co-traffic');
    expect(on.batchedRows, prompts.length,
        reason: 'W-G2: every gate row was batched');
    expect(on.soloFallbackRows, 0, reason: 'W-G2: zero fallback rows');

    // ---- W-G1: byte-equal payloads, per prompt, solo vs fused.
    for (var i = 0; i < prompts.length; i++) {
      expect(
        concurrent[i],
        soloBodies[i],
        reason: 'W-G1 row $i: fused answer diverged from solo\n'
            'solo: ${jsonEncode(soloBodies[i])}\n'
            'fused: ${jsonEncode(concurrent[i])}',
      );
    }

    // ---- Reported, not gated: a free-form prompt through a concurrent
    // PAIR (the tie-flip regime). Agreement is a recorded fact only.
    const freeForm =
        'Write one short sentence about the sea. Do not use the word water.';
    final freeSolo = await chat(off.url, freeForm, maxTokens: 24);
    final freePair = await Future.wait<Map<String, dynamic>>([
      chat(on.url, freeForm, maxTokens: 24),
      chat(on.url, 'Write one short sentence about the mountains.', maxTokens: 24),
    ]);
    final agree = freePair.first['choices'][0]['message']['content'] ==
        freeSolo['choices'][0]['message']['content'];
    stdout.writeln(
      'free-form solo-vs-coalesced agreement (reported, not gated): $agree',
    );

    expect(soloBodies.length, prompts.length);
  });
}
