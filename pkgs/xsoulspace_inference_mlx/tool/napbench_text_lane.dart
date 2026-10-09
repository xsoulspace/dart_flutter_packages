#!/usr/bin/env dart

/// napbench text-lane: TTFT/decode benchmarks for the native MLX text lane
/// against the ADR 0051 acceptance table (decision 2 — the harness workload:
/// 2k–8k-token prefills, interleaved generation, 4-bit models).
///
///   dart run tool/napbench_text_lane.dart [--models qwen06,qwen17,lfm25]
///       [--runs 7] [--prefill 2000,4000,8000] [--decode-tokens 128] [--json]
///
/// Per model: engine load time, RSS, prefill time (engine-reported) and
/// wall TTFT at each prefill target, decode tok/s p50/p95 over [runs]
/// generations of a nap-style prompt, and the verdict against the two
/// acceptance rows that name this lane (TTFT@4k ≤ 300 ms; LFM2.5-1.2B
/// decode p50 ≥ 45 tok/s). Measured through the same in-process engine the
/// serve runtime uses — loopback transport overhead is not part of these
/// numbers.
///
/// Native-line confirmation (py-retirement 2026-10-09): this lane measures
/// ONLY the in-process native engine (`NativeMlxTextEngine` — no python
/// mlx_lm, no external server leg, no spawn). Python `mlx_lm` is retired
/// to benchmark REFERENCE legs (run separately, compared against — e.g.
/// the harness nap_draft_benchmark py-reference leg) and golden/fixture
/// recording; it never appears as a row here.
///
/// Models resolve from the local HF cache (`mlx-community/Qwen3-0.6B-4bit`,
/// `mlx-community/Qwen3-1.7B-4bit`, `LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit`)
/// and are never downloaded. Qwen3 runs with thinking mode OFF (the napbench
/// faithfulness requirement).
library;

import 'dart:io';

import 'package:xsoulspace_inference_mlx/xsoulspace_inference_mlx.dart';

final class _Model {
  const _Model(this.name, this.repo, {this.noThink = false});

  final String name;
  final String repo;

  /// Qwen3-style soft switch: thinking mode off (napbench requirement).
  final bool noThink;
}

const _models = <String, _Model>{
  'qwen06': _Model('Qwen3-0.6B-4bit', 'models--mlx-community--Qwen3-0.6B-4bit',
      noThink: true),
  'qwen17': _Model('Qwen3-1.7B-4bit', 'models--mlx-community--Qwen3-1.7B-4bit',
      noThink: true),
  'lfm25': _Model('LFM2.5-1.2B-4bit',
      'models--LiquidAI--LFM2.5-1.2B-Instruct-MLX-4bit'),
};

const _napPrompt =
    'Draft a one-line summary (max 280 bytes) of this memory record:\n'
    'The runner reconciles claims and acceptance across the shared '
    'workspace; a stale index refuses loudly rather than answering from '
    'stale data, and every rebuild is incremental.\nOne line:';

/// Harness-shaped filler text: repeated working-agreement prose, ~22
/// tokens per repetition, so prompt token counts land near the targets.
const _filler =
    'The runner reconciles claims and acceptance across the shared '
    'workspace world; a stale index refuses loudly rather than answering '
    'from stale data. ';

Never _fail(final String message) {
  stderr.writeln(message);
  exit(2);
}

String _argValue(final List<String> args, final String name) {
  final index = args.indexOf('--$name');
  return index >= 0 && index + 1 < args.length ? args[index + 1] : '';
}

Future<void> main(final List<String> arguments) async {
  final modelKeys = _argValue(arguments, 'models').isEmpty
      ? const <String>['qwen06']
      : _argValue(arguments, 'models').split(',');
  if (modelKeys.length != 1) {
    _fail(
      'bench ONE model per process: mlx wired-memory pressure from model '
      'succession and repeated fresh-KV prefills contaminates later numbers '
      '(observed: decode 45 → 7 tok/s when a second model loads into the '
      'same process). Pass exactly one of: ${_models.keys.join(', ')}',
    );
  }
  final runs = _argValue(arguments, 'runs').isEmpty
      ? 7
      : int.parse(_argValue(arguments, 'runs'));
  final prefillReps = _argValue(arguments, 'prefill-reps').isEmpty
      ? 3
      : int.parse(_argValue(arguments, 'prefill-reps'));
  final prefillTargets = (_argValue(arguments, 'prefill').isEmpty
          ? '2000,4000,8000'
          : _argValue(arguments, 'prefill'))
      .split(',')
      .map(int.parse)
      .toList();
  final decodeTokens = _argValue(arguments, 'decode-tokens').isEmpty
      ? 128
      : int.parse(_argValue(arguments, 'decode-tokens'));
  final asJson = arguments.contains('--json');
  // --warm keeps every rep's prompt identical so the engine's cross-request
  // KV prefix reuse hides prefill (drafting-lane shape); default is a fresh
  // nonce per rep — the cold prefill the TTFT target is about.
  final warm = arguments.contains('--warm');
  // Prefill shaping passed through to the engine: --prefill-step N caps
  // tokens per prefill forward, --unchunked runs one forward for the whole
  // prompt. Default: the engine's own default (balanced, 512-step).
  final prefillStep = _argValue(arguments, 'prefill-step').isEmpty
      ? null
      : int.parse(_argValue(arguments, 'prefill-step'));
  final unchunked = arguments.contains('--unchunked');

  for (final key in modelKeys) {
    final model = _models[key];
    if (model == null) {
      _fail('unknown model "$key" (known: ${_models.keys.join(', ')})');
    }
    final snapshot = _resolveSnapshot(model.repo);
    if (asJson) {
      stdout.writeln(
        await _bench(model, snapshot, runs, prefillTargets, decodeTokens,
            json: true, warm: warm, prefillStep: prefillStep,
            unchunked: unchunked, prefillReps: prefillReps),
      );
    } else {
      stdout.writeln(
        await _bench(model, snapshot, runs, prefillTargets, decodeTokens,
            warm: warm, prefillStep: prefillStep, unchunked: unchunked,
            prefillReps: prefillReps),
      );
    }
  }
}

String _resolveSnapshot(final String repo) {
  final hub = Platform.environment['HF_HOME'] != null
      ? '${Platform.environment['HF_HOME']}/hub'
      : '${Platform.environment['HOME'] ?? ''}/.cache/huggingface/hub';
  final snapshots = Directory('$hub/$repo/snapshots');
  if (!snapshots.existsSync()) {
    _fail('no cached snapshot for $repo under $hub (the bench never '
        'downloads; fetch the repo first)');
  }
  for (final entry in snapshots.listSync()) {
    if (entry is Directory && File('${entry.path}/config.json').existsSync()) {
      return entry.path;
    }
  }
  _fail('snapshot for $repo has no config.json');
}

Future<String> _bench(
  final _Model model,
  final String snapshot,
  final int runs,
  final List<int> prefillTargets,
  final int decodeTokens, {
  final bool json = false,
  final bool warm = false,
  final int? prefillStep,
  final bool unchunked = false,
  final int prefillReps = 3,
}) async {
  MlxNativeRequest request({
    required final String prompt,
    required final int maxTokens,
  }) => MlxNativeRequest(
    prompt: prompt,
    maxTokens: maxTokens,
    prefillStep: prefillStep,
    prefillUnchunked: unchunked,
    templateArgs: model.noThink
        ? const <String, Object?>{'enable_thinking': false}
        : null,
  );
  final loadWatch = Stopwatch()..start();
  final engine = await NativeMlxTextEngine.load(snapshot);
  loadWatch.stop();
  final rssAfterLoad = ProcessInfo.currentRss;
  try {
    // Warmup: pages in weights + stabilizes the isolate pool.
    await engine.generate(request(prompt: _napPrompt, maxTokens: 8));

    // Prefill: engine-reported prompt time + wall time to a 1-token
    // completion, median of 3 per target. Every rep prepends a fresh
    // nonce so the engine's cross-request KV prefix reuse never kicks in
    // — each rep pays the full cold prefill the TTFT target is about.
    final prefillRows = <Map<String, Object?>>[];
    for (final target in prefillTargets) {
      final promptMs = <int>[];
      final wallMs = <int>[];
      final templateMs = <int>[];
      var promptTokens = 0;
      for (var i = 0; i < prefillReps; i++) {
        final prompt = warm
            ? _fillerPrompt(target)
            : '[bench ${target}tok rep $i]\n${_fillerPrompt(target)}';
        final watch = Stopwatch()..start();
        final generation = await engine.generate(
          request(prompt: prompt, maxTokens: 1),
        );
        watch.stop();
        promptMs.add(generation.promptTimeMs);
        wallMs.add(watch.elapsedMilliseconds);
        templateMs.add(generation.templateMs);
        promptTokens = generation.promptTokens;
      }
      prefillRows.add({
        'target': target,
        'prompt_tokens': promptTokens,
        'prefill_ms_p50': _p50(promptMs),
        'ttft_ms_p50': _p50(wallMs),
        'ttft_walls': wallMs.join('/'),
        'template_ms_p50': _p50(templateMs),
      });
    }

    // Decode: tok/s per generation over a nap-style prompt.
    final tokPerSec = <double>[];
    final decodeWall = <int>[];
    var decodePromptTokens = 0;
    var maxRss = rssAfterLoad;
    for (var i = 0; i < runs; i++) {
      final watch = Stopwatch()..start();
      final generation = await engine.generate(
        request(prompt: _napPrompt, maxTokens: decodeTokens),
      );
      watch.stop();
      decodeWall.add(watch.elapsedMilliseconds);
      decodePromptTokens = generation.promptTokens;
      if (generation.generateTimeMs > 0) {
        tokPerSec.add(generation.completionTokens * 1000 /
            generation.generateTimeMs);
      }
      final rss = ProcessInfo.currentRss;
      if (rss > maxRss) maxRss = rss;
    }
    tokPerSec.sort();

    return json
        ? _jsonLine(model, loadWatch.elapsedMilliseconds, rssAfterLoad, maxRss,
            prefillRows, decodePromptTokens, tokPerSec, decodeWall)
        : _table(model, loadWatch.elapsedMilliseconds, rssAfterLoad, maxRss,
            prefillRows, decodePromptTokens, tokPerSec, decodeWall,
            prefillMode: unchunked
                ? 'unchunked'
                : prefillStep == null
                ? 'default'
                : 'step $prefillStep');
  } finally {
    engine.unload();
  }
}

String _fillerPrompt(final int targetTokens) {
  final buffer = StringBuffer();
  while (buffer.length < targetTokens * 4) {
    buffer.write(_filler);
  }
  buffer.write('Summarize the state above in one line.');
  return buffer.toString();
}

int _p50(final List<int> values) {
  final sorted = List<int>.of(values)..sort();
  return sorted[(sorted.length * 0.5).floor().clamp(0, sorted.length - 1)];
}

double _percentile(final List<double> values, final double fraction) {
  final sorted = List<double>.of(values)..sort();
  final index = (fraction * (sorted.length - 1)).round();
  return sorted[index];
}

String _table(
  final _Model model,
  final int loadMs,
  final int rssAfterLoad,
  final int maxRss,
  final List<Map<String, Object?>> prefillRows,
  final int decodePromptTokens,
  final List<double> tokPerSec,
  final List<int> decodeWall, {
  final String prefillMode = 'default',
}) {
  final buffer = StringBuffer()
    ..writeln(
      '== ${model.name} — load ${loadMs}ms, '
      'RSS ${_mb(rssAfterLoad)}→${_mb(maxRss)} MB, prefill mode: $prefillMode',
    );
  for (final row in prefillRows) {
    buffer.writeln(
      'prefill ~${row['target']}tok (actual ${row['prompt_tokens']}): '
      '${row['prefill_ms_p50']}ms engine / ${row['ttft_ms_p50']}ms wall '
      '(walls ${row['ttft_walls']}, template ${row['template_ms_p50']}ms)',
    );
  }
  if (tokPerSec.isEmpty) {
    buffer.writeln('decode: no completed generations');
    return '$buffer';
  }
  final decodeP50 = _percentile(tokPerSec, 0.5);
  final decodeP95 = _percentile(tokPerSec, 0.95);
  final wallP50 = _p50(decodeWall);
  buffer
    ..writeln(
      'decode (${tokPerSec.length} runs, prompt $decodePromptTokens tok, '
      'wall p50 ${wallP50}ms): tok/s p50 ${decodeP50.toStringAsFixed(1)}, '
      'p95 ${decodeP95.toStringAsFixed(1)}',
    )
    ..writeln(_verdict(model, prefillRows, decodeP50));
  return '$buffer';
}

String _jsonLine(
  final _Model model,
  final int loadMs,
  final int rssAfterLoad,
  final int maxRss,
  final List<Map<String, Object?>> prefillRows,
  final int decodePromptTokens,
  final List<double> tokPerSec,
  final List<int> decodeWall,
) {
  return '''
{"model": "${model.name}", "repo": "${model.repo}", "load_ms": $loadMs,
 "rss_after_load_mb": ${_mb(rssAfterLoad)}, "rss_max_mb": ${_mb(maxRss)},
 "prefill": [${[
    for (final row in prefillRows)
      '{"target": ${row['target']}, "prompt_tokens": ${row['prompt_tokens']}, '
          '"prefill_ms_p50": ${row['prefill_ms_p50']}, '
          '"ttft_ms_p50": ${row['ttft_ms_p50']}, '
          '"ttft_walls": "${row['ttft_walls']}", '
          '"template_ms_p50": ${row['template_ms_p50']}}'
  ].join(', ')}],
 "decode_prompt_tokens": $decodePromptTokens,
 "decode_tok_s_p50": ${tokPerSec.isEmpty ? 'null' : _percentile(tokPerSec, 0.5).toStringAsFixed(1)},
 "decode_tok_s_p95": ${tokPerSec.isEmpty ? 'null' : _percentile(tokPerSec, 0.95).toStringAsFixed(1)},
 "decode_wall_ms_p50": ${tokPerSec.isEmpty ? 'null' : _p50(decodeWall)}}'''
      .replaceAll('\n', ' ');
}

String _verdict(
  final _Model model,
  final List<Map<String, Object?>> prefillRows,
  final double decodeP50,
) {
  final ttft4k = prefillRows
      .where((row) => (row['prompt_tokens'] as int) >= 3800)
      .map((row) => row['ttft_ms_p50'] as int)
      .toList();
  final verdicts = <String>[];
  if (ttft4k.isNotEmpty) {
    final worst = ttft4k.reduce((a, b) => a > b ? a : b);
    verdicts.add(
      'TTFT@4k ${worst}ms ${worst <= 300 ? 'MEETS' : 'MISSES'} the ≤300ms '
          'target',
    );
  }
  if (model.name.startsWith('LFM2.5')) {
    verdicts.add(
      'decode p50 ${decodeP50.toStringAsFixed(1)} tok/s '
      '${decodeP50 >= 45 ? 'MEETS' : 'MISSES'} the ≥45 tok/s target',
    );
  }
  return verdicts.isEmpty ? '' : 'verdict: ${verdicts.join('; ')}';
}

String _mb(final int bytes) => (bytes / (1024 * 1024)).round().toString();
