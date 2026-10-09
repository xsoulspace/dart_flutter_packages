#!/usr/bin/env dart
/// model_bench_suite — the three-lane quality/latency bench for the local
/// production line (ADR 0057): `chat`, `decompression`, `swe`.
///
/// Wire-level by design: it benches whatever OpenAI-compatible loopback
/// endpoint is cast (the native line, a spawned server, a python
/// reference) — the same wire the harness palette consumes. `--in-process
/// qwen` bundles the native qwen chat server so one command benches the
/// engine directly.
///
/// ```dart run tool/model_bench_suite.dart --in-process qwen```
///   dart run tool/model_bench_suite.dart --endpoint http://127.0.0.1:8765
///       [--lane chat,decompression,swe] [--out bench]
///
/// Checkers are deterministic (containment / byte caps / compile+run) —
/// no LLM judge. Scorecards are advisory until two runs exist (ADR 0057:
/// unmeasured numbers are non-claims); then thresholds get pinned in the
/// ADR. Output: bench/scorecard-<stamp>.json + a markdown table on stdout.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xsoulspace_inference_laya/xsoulspace_inference_laya.dart';

const _lanes = ['chat', 'decompression', 'swe'];

void main(final List<String> args) async {
  String? endpointArg;
  String? inProcess;
  var raw = false;
  var lanes = _lanes.toList();
  var outDir = 'bench';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--endpoint':
        endpointArg = args[++i];
      case '--in-process':
        inProcess = args[++i];
      case '--raw':
        raw = true;
      case '--lane':
        lanes = args[++i].split(',');
      case '--out':
        outDir = args[++i];
      case '--help' || '-h':
        print(_usage);
        return;
      default:
        _fail('unknown arg ${args[i]}\n$_usage');
    }
  }
  if (endpointArg == null && inProcess == null) {
    _fail('need --endpoint or --in-process\n$_usage');
  }
  if (lanes.any((final l) => !_lanes.contains(l))) {
    _fail('lanes must be a subset of $_lanes');
  }

  late final Uri base;
  // Both chat servers expose start/stop/url (no shared supertype).
  dynamic server;
  if (endpointArg != null) {
    base = Uri.parse(endpointArg);
    final health = await http.get(base.replace(path: '/health'));
    if (health.statusCode != 200) {
      _fail('endpoint $base /health returned ${health.statusCode}');
    }
  } else {
    if (inProcess != 'qwen' && inProcess != 'lfm2') {
      _fail("--in-process supports qwen|lfm2, optional --raw "
          '(legacy no-template cast); --endpoint covers any wire server)');
    }
    // The bundled native line: load + serve in-process, no python.
    // (The two chat servers share the wire contract, not a supertype.)
    // `--raw` selects the legacy no-template/no-EOS cast — the bench's
    // controlled comparison cell (ADR 0057: same model, same lanes).
    if (inProcess == 'qwen') {
      server = LayaQwenChatServer(
        engine: await NativeQwenTextEngine.load(),
        useTemplate: !raw,
      );
    } else {
      server = LayaLfm2ChatServer(
        engine: await NativeLfm2TextEngine.load(),
        useTemplate: !raw,
      );
    }
    await server.start();
    base = server.url;
    stderr.writeln(
      'in-process native line ($inProcess, template${raw ? ' off' : ''}) '
      'at ${server.url}',
    );
  }

  final results = <_LaneResult>[];
  try {
    for (final lane in lanes) {
      final file = File('testdata/bench/${lane}_lane.json');
      if (!file.existsSync()) {
        stderr.writeln('lane file missing: ${file.path} — skipping');
        continue;
      }
      final spec =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      results.add(
        switch (lane) {
          'chat' => await _runChat(base, spec),
          'decompression' => await _runDecompression(base, spec),
          'swe' => await _runSwe(base, spec),
          _ => throw StateError('unreachable'),
        },
      );
    }
  } finally {
    server?.stop();
  }

  final stamp = DateTime.now().toUtc().toIso8601String();
  final scorecard = <String, Object?>{
    'bench': 'model_bench_suite',
    'endpoint': base.toString(),
    'recorded_utc': stamp,
    'lanes': [
      for (final r in results)
        <String, Object?>{
          'lane': r.lane,
          'passed': r.passed,
          'total': r.total,
          'pass_rate': r.total == 0 ? 0 : r.passed / r.total,
          'p50_wall_ms': _pct(r.walls, 0.5),
          'tok_s_median': _pct(r.tokRates, 0.5),
          'cases': [for (final c in r.cases) c.toMap()],
        },
    ],
  };
  Directory(outDir).createSync(recursive: true);
  final path =
      '$outDir/scorecard-${stamp.replaceAll(RegExp(r'[:.]'), '-')}.json';
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(scorecard));

  _printMarkdown(scorecard, path);
}

String get _usage =>
    'usage: dart run tool/model_bench_suite.dart (--endpoint URL | '
    '--in-process qwen) [--lane chat,decompression,swe] [--out bench]';

Never _fail(final String message) {
  stderr.writeln(message);
  exit(2);
}

// ---- one completion over the OpenAI-compatible wire ----

Future<_Completion> _complete(
  final Uri base,
  final List<Map<String, String>> messages,
  final int maxTokens,
) async {
  final t0 = DateTime.now();
  final reply = await http.post(
    base.replace(path: '/v1/chat/completions'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'model': 'bench',
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': 0,
    }),
  );
  final wall = DateTime.now().difference(t0);
  if (reply.statusCode != 200) {
    return _Completion(
      text: '',
      wall: wall,
      completionTokens: 0,
      error: 'HTTP ${reply.statusCode}: ${reply.body.substring(0, reply.body.length.clamp(0, 200))}',
    );
  }
  final body = jsonDecode(reply.body) as Map<String, dynamic>;
  final choices = body['choices'] as List?;
  final content = choices == null || choices.isEmpty
      ? ''
      : (((choices.first as Map)['message'] as Map)['content'] ?? '') as String;
  final usage = body['usage'] as Map?;
  return _Completion(
    text: content,
    wall: wall,
    completionTokens: usage?['completion_tokens'] as int? ?? 0,
  );
}

double _pct(final List<double> xs, final double p) {
  if (xs.isEmpty) return 0;
  final s = xs.toList()..sort();
  return s[((s.length - 1) * p).round()];
}

// ---- lanes ----

class _CaseResult {
  _CaseResult({
    required this.id,
    required this.ok,
    required this.wallMs,
    required this.tokS,
    this.reason,
  });

  final String id;
  final bool ok;
  final double wallMs;
  final double tokS;
  final String? reason;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'ok': ok,
    'wall_ms': wallMs.round(),
    'tok_s': double.parse(tokS.toStringAsFixed(1)),
    if (reason != null) 'reason': reason,
  };
}

class _LaneResult {
  _LaneResult(this.lane, this.cases)
    : passed = cases.where((final c) => c.ok).length,
      total = cases.length,
      walls = [for (final c in cases) c.wallMs],
      tokRates = [for (final c in cases) c.tokS];

  final String lane;
  final List<_CaseResult> cases;
  final int passed;
  final int total;
  final List<double> walls;
  final List<double> tokRates;
}

class _Completion {
  const _Completion({
    required this.text,
    required this.wall,
    required this.completionTokens,
    this.error,
  });

  final String text;
  final Duration wall;
  final int completionTokens;
  final String? error;

  double get tokS =>
      completionTokens / (wall.inMilliseconds / 1000.0).clamp(0.001, 1e9);
}

Future<_LaneResult> _runChat(
  final Uri base,
  final Map<String, dynamic> spec,
) async {
  final cases = <_CaseResult>[];
  for (final raw in spec['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    final completion = await _complete(
      base,
      [
        for (final m in c['messages'] as List)
          {
            'role': (m as Map)['role'] as String,
            'content': m['content'] as String,
          },
      ],
      c['max_tokens'] as int,
    );
    final check = _checkContains(c, completion);
    cases.add(_CaseResult(
      id: c['id'] as String,
      ok: check.ok,
      wallMs: completion.wall.inMilliseconds.toDouble(),
      tokS: completion.tokS,
      reason: check.reason,
    ));
  }
  return _LaneResult('chat', cases);
}

Future<_LaneResult> _runDecompression(
  final Uri base,
  final Map<String, dynamic> spec,
) async {
  final cap = spec['max_output_bytes'] as int;
  final minHits = spec['min_entity_hits'] as int;
  final cases = <_CaseResult>[];
  for (final raw in spec['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    final completion = await _complete(base, [
      {
        'role': 'user',
        'content':
            'Summarize this memory record as ONE line of at most $cap bytes '
            '(keep the key facts and names):\n${c['record']}\nOne line:',
      },
    ], c['max_tokens'] as int);
    final text = completion.text.trim();
    final bytes = utf8.encode(text).length;
    final oneLine = !text.contains('\n');
    final entities = (c['entities'] as List).cast<String>();
    final hits = [for (final e in entities) if (text.contains(e)) e];
    final reasons = <String>[
      if (completion.error != null) completion.error!,
      if (bytes > cap) 'output $bytes bytes > $cap cap',
      if (!oneLine) 'output is not a single line',
      if (hits.length < minHits)
        'entity recall ${hits.length}/$minHits of ${entities.length}',
    ];
    cases.add(_CaseResult(
      id: c['id'] as String,
      ok: reasons.isEmpty,
      wallMs: completion.wall.inMilliseconds.toDouble(),
      tokS: completion.tokS,
      reason: reasons.isEmpty ? null : reasons.join('; '),
    ));
  }
  return _LaneResult('decompression', cases);
}

Future<_LaneResult> _runSwe(
  final Uri base,
  final Map<String, dynamic> spec,
) async {
  final timeoutSec = spec['timeout_seconds'] as int;
  final cases = <_CaseResult>[];
  for (final raw in spec['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    final completion = await _complete(base, [
      {'role': 'user', 'content': c['prompt'] as String},
    ], 256);
    final code = _extractDart(completion.text);
    if (code == null) {
      cases.add(_CaseResult(
        id: c['id'] as String,
        ok: false,
        wallMs: completion.wall.inMilliseconds.toDouble(),
        tokS: completion.tokS,
        reason: 'no dart function found in output',
      ));
      continue;
    }
    final result = await _runDartHarness(
      code,
      c['harness'] as String,
      Duration(seconds: timeoutSec),
    );
    cases.add(_CaseResult(
      id: c['id'] as String,
      ok: result.exitCode == 0,
      wallMs: completion.wall.inMilliseconds.toDouble(),
      tokS: completion.tokS,
      reason: result.exitCode == 0 ? null : result.stderr.trim(),
    ));
  }
  return _LaneResult('swe', cases);
}

/// Fenced block first, else the raw text (the model was told function-only).
String? _extractDart(final String text) {
  final fence = RegExp(r'```(?:dart)?\s*\n(.*?)```', dotAll: true)
      .firstMatch(text)
      ?.group(1)
      ?.trim();
  final body = fence ?? text.trim();
  return body.isEmpty ? null : body;
}

Future<ProcessResult> _runDartHarness(
  final String function,
  final String harness,
  final Duration timeout,
) async {
  final dir = await Directory.systemTemp.createTemp('bench_swe_');
  try {
    final file = File('${dir.path}/main.dart');
    file.writeAsStringSync('$function\n\n$harness\n\nvoid main() { run(); }\n');
    return await Process.run(
      'dart',
      [file.path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(timeout, onTimeout: () => ProcessResult(-1, -1, '', 'timed out'));
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// chat checker: containment on the completion text.
_CheckResult _checkContains(
  final Map<String, dynamic> c,
  final _Completion completion,
) {
  final text = completion.text;
  final reasons = <String>[
    if (completion.error != null) completion.error!,
    for (final e in (c['expect_all'] as List?) ?? <dynamic>[])
      if (!text.contains(e as String)) 'missing "$e"',
  ];
  final anyList = (c['expect_any'] as List?)?.cast<String>();
  if (anyList != null && anyList.isNotEmpty && !anyList.any(text.contains)) {
    reasons.add('none of $anyList found');
  }
  return (ok: reasons.isEmpty, reason: reasons.isEmpty ? null : reasons.join('; '));
}

typedef _CheckResult = ({bool ok, String? reason});

void _printMarkdown(
  final Map<String, dynamic> scorecard,
  final String path,
) {
  print('# model_bench_suite — ${scorecard['recorded_utc']}');
  print('endpoint: ${scorecard['endpoint']}');
  print('');
  print('| lane | pass | p50 wall ms | p50 tok/s |');
  print('|---|---|---|---|');
  for (final l in scorecard['lanes'] as List) {
    final lane = l as Map<String, dynamic>;
    print(
      '| ${lane['lane']} | ${lane['passed']}/${lane['total']} '
      '(${((lane['pass_rate'] as double) * 100).toStringAsFixed(0)}%) '
      '| ${lane['p50_wall_ms']} | ${lane['tok_s_median']} |',
    );
  }
  print('');
  print('scorecard: $path');
  print('advisory until two runs exist (ADR 0057); failures:');
  for (final l in scorecard['lanes'] as List) {
    final lane = l as Map<String, dynamic>;
    for (final c in lane['cases'] as List) {
      final kase = c as Map<String, dynamic>;
      if (kase['ok'] != true) print('  [${lane['lane']}] ${kase['id']}: ${kase['reason']}');
    }
  }
}
