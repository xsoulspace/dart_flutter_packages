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
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

const _lanes = ['chat', 'decompression', 'swe', 'tools', 'laya'];

/// The cast budget switches, set by main() before lanes run (the lane
/// runners read them via [_budgetFor]).
var thinking = false;
var lfm26bThinking = false;

void main(final List<String> args) async {
  String? endpointArg;
  String? inProcess;
  var raw = false;
  String? qwenSnapshot;
  String? lfmSnapshot;
  var lfm26b = false;
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
      case '--thinking':
        thinking = true;
      case '--qwen-snapshot':
        qwenSnapshot = args[++i];
      case '--lfm-snapshot':
        lfmSnapshot = args[++i];
      case '--lfm-26b':
        lfm26b = true;
        // The 2.6B variant always reasons (think-open generation prompt);
        // its cast budget law follows automatically.
        lfm26bThinking = true;
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
  if (inProcess == 'laya') {
    // The decision model is not a chat model — it runs its own lane over
    // the golden fixture (agreement + decision latency), no wire.
    lanes = ['laya'];
  }
  if (lanes.any((final l) => !_lanes.contains(l))) {
    _fail('lanes must be a subset of $_lanes');
  }

  late Uri base;
  // Both chat servers expose start/stop/url (no shared supertype).
  dynamic server;
  if (inProcess == 'laya') {
    // The decision model is not a chat model — its lane runs in-process
    // over the golden fixture; no wire, no server.
    base = Uri.parse('http://127.0.0.1:0');
  } else if (endpointArg != null) {
    base = Uri.parse(endpointArg);
    final health = await http.get(base.replace(path: '/health'));
    if (health.statusCode != 200) {
      _fail('endpoint $base /health returned ${health.statusCode}');
    }
  } else if (inProcess == 'qwen' || inProcess == 'lfm2') {
    if (thinking && inProcess != 'qwen') {
      _fail('--thinking applies to qwen only (LFM2.5-Instruct ships no '
          'thinking switch — recorded non-claim; --lfm-26b carries its own '
          'reasoning budget automatically)');
    }
    if (inProcess == 'qwen') {
      server = LayaQwenChatServer(
        engine: await NativeQwenTextEngine.load(snapshotDir: qwenSnapshot),
        useTemplate: !raw,
        thinking: thinking,
      );
    } else {
      server = LayaLfm2ChatServer(
        engine: await NativeLfm2TextEngine.load(snapshotDir: lfmSnapshot),
        useTemplate: !raw,
        variant: lfm26b
            ? Lfm2ChatTemplateVariant.lfm25_26b
            : Lfm2ChatTemplateVariant.lfm25_12b,
        model: lfm26b ? 'lfm2.5-2.6b-mlx-4bit' : 'lfm2.5-1.2b-instruct-mlx-4bit',
      );
    }
    await server.start();
    base = server.url;
    stderr.writeln(
      'in-process native line ($inProcess${lfm26b ? '-2.6b' : ''}, '
      'template${raw ? ' off' : ''}'
      '${thinking ? ', thinking' : ''}) at ${server.url}',
    );
  } else {
    _fail("--in-process supports qwen|lfm2|laya, optional --raw/--thinking; "
        '--endpoint covers any wire server)');
  }

  final results = <_LaneResult>[];
  try {
    for (final lane in lanes) {
      if (lane != 'laya') {
        final file = File('testdata/bench/${lane}_lane.json');
        if (!file.existsSync()) {
          stderr.writeln('lane file missing: ${file.path} — skipping');
          continue;
        }
      }
      final spec = lane == 'laya'
          ? const <String, dynamic>{}
          : jsonDecode(
                  File('testdata/bench/${lane}_lane.json').readAsStringSync())
              as Map<String, dynamic>;
      results.add(
        switch (lane) {
          'chat' => await _runChat(base, spec, thinking),
          'decompression' => await _runDecompression(base, spec, thinking),
          'swe' => await _runSwe(base, spec, thinking),
          'tools' => await _runTools(base, spec, thinking),
          'laya' => await _runLaya(),
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

/// The generation budget for one case. The lfm25-26b variant ALWAYS
/// reasons before its answer (the template opens the think block), so its
/// cast carries its own measured budget: 5× the case cap, floored at 384
/// tokens (measured 2026-10-09: the 2.6B's reasoning alone exceeds 3× on
/// the decompression records; with 400 it closes and answers cleanly).
/// Qwen3's `--thinking` keeps its ×3 (the recorded thinking cells).
int _budgetFor(final int base) =>
    lfm26bThinking
        ? (base * 5).clamp(384, 1 << 31)
        : (thinking ? base * 3 : base);

Future<_Completion> _complete(
  final Uri base,
  final List<Map<String, String>> messages,
  final int maxTokens, {
  final List<Object?>? tools,
}) async {
  final t0 = DateTime.now();
  final reply = await http.post(
    base.replace(path: '/v1/chat/completions'),
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(<String, Object?>{
      'model': 'bench',
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': 0,
      'tools': ?tools,
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

/// Strips `<think>…</think>` reasoning so the checkers judge the answer;
/// an unclosed `<think>` (the generation budget ran out mid-reasoning)
/// cuts from its start — the case then honestly fails containment.
String _answerOf(final String text) {
  final stripped = text.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>'),
    '',
  );
  final open = stripped.indexOf('<think>');
  return (open >= 0 ? stripped.substring(0, open) : stripped).trim();
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
  final bool thinking,
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
      _budgetFor(c['max_tokens'] as int),
    );
    final check = _checkContains(c, _Completion(
      text: _answerOf(completion.text),
      wall: completion.wall,
      completionTokens: completion.completionTokens,
    ));
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
  final bool thinking,
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
    ], _budgetFor(c['max_tokens'] as int));
    final text = _answerOf(completion.text);
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
  final bool thinking,
) async {
  final timeoutSec = spec['timeout_seconds'] as int;
  final cases = <_CaseResult>[];
  for (final raw in spec['cases'] as List) {
    final c = raw as Map<String, dynamic>;
    final completion = await _complete(base, [
      {'role': 'user', 'content': c['prompt'] as String},
    ], _budgetFor(256));
    final sweText = _answerOf(completion.text);
    final code = _extractDart(sweText);
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

/// The tools lane (ADR 0058 tools rung): the model must emit its tool
/// call in the checkpoint's own textual format. The checker is
/// format-tolerant (Qwen3 `<tool_call>{json}</tool_call>`, Liquid
/// `<|tool_call_start|>…<|tool_call_end|>`, bare JSON objects) and
/// strict on semantics: the called name must equal the expected tool and
/// every expected argument must match. A `call_tool: false` case fails
/// when the model invents a call.
Future<_LaneResult> _runTools(
  final Uri base,
  final Map<String, dynamic> spec,
  final bool thinking,
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
      _budgetFor(c['max_tokens'] as int),
      tools: (c['tools'] as List?)?.toList(),
    );
    final text = completion.text;
    final reasons = <String>[if (completion.error != null) completion.error!];
    final wantTool = c['call_tool'] == false ? null : c['expect_tool'] as String;
    final calls = _extractToolCalls(text);
    if (wantTool == null) {
      if (calls.isNotEmpty) {
        reasons.add('expected no tool call, found ${calls.map((c) => c.name)}');
      }
    } else {
      if (calls.isEmpty) {
        reasons.add('no tool call found in output: <${text.trim()}>');
      } else if (!calls.any((final call) => call.name == wantTool)) {
        reasons.add(
          'called ${calls.map((c) => c.name)} != expected $wantTool',
        );
      } else {
        final call = calls.firstWhere((final call) => call.name == wantTool);
        for (final entry in (c['expect_args'] as Map?)?.entries ??
            const Iterable<MapEntry<dynamic, dynamic>>.empty()) {
          final key = '${entry.key}';
          final got = call.args[key];
          final want = '${entry.value}';
          if (got == null) {
            reasons.add('missing argument $key');
          } else if ('${got is num ? numToCompact(got) : got}' != want &&
              '$got' != want) {
            reasons.add('argument $key = $got != $want');
          }
        }
      }
    }
    cases.add(_CaseResult(
      id: c['id'] as String,
      ok: reasons.isEmpty,
      wallMs: completion.wall.inMilliseconds.toDouble(),
      tokS: completion.tokS,
      reason: reasons.isEmpty ? null : reasons.join('; '),
    ));
  }
  return _LaneResult('tools', cases);
}

String numToCompact(final num n) =>
    n is int ? '$n' : n.toStringAsFixed(0).replaceAll(RegExp(r'\.0$'), '');

class _ToolCall {
  _ToolCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

/// Pulls tool calls out of a completion in any of the shapes the local
/// checkpoints emit: `<tool_call>{json}</tool_call>` (Qwen3),
/// `<|tool_call_start|>[…]<|tool_call_end|>` (Liquid, python-repr or
/// JSON), or a bare JSON object with name+arguments.
List<_ToolCall> _extractToolCalls(final String text) {
  final calls = <_ToolCall>[];
  // End tags are optional in the match: a budget-capped completion may
  // stop right after the call (measured on the 2.6B).
  final block = RegExp(
    r'<tool_call>\s*([\s\S]*?)\s*(?:</tool_call>|$)|'
    r'<\|tool_call_start\|>\s*([\s\S]*?)\s*(?:<\|tool_call_end\|>|$)',
  );
  for (final m in block.allMatches(text)) {
    final payload = (m.group(1) ?? m.group(2) ?? '').trim();
    final call = _parseCallPayload(payload) ?? _scanCallName(payload);
    if (call != null) calls.add(call);
  }
  if (calls.isEmpty) {
    // Bare JSON object (no wrapper tags).
    final brace = text.indexOf('{');
    if (brace >= 0) {
      final call = _parseCallPayload(text.substring(brace).trim());
      if (call != null) calls.add(call);
    }
  }
  return calls;
}

_ToolCall? _parseCallPayload(final String payload) {
  for (final candidate in _jsonCandidates(payload)) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is List) {
        for (final element in decoded) {
          if (element is Map && element['name'] is String) {
            return _ToolCall(
              element['name'] as String,
              element['arguments'] is Map
                  ? (element['arguments'] as Map).cast<String, dynamic>()
                  : const {},
            );
          }
        }
      } else if (decoded is Map && decoded['name'] is String) {
        return _ToolCall(
          decoded['name'] as String,
          decoded['arguments'] is Map
              ? (decoded['arguments'] as Map).cast<String, dynamic>()
              : const {},
        );
      }
    } on FormatException {
      continue;
    }
  }
  return _parseSignatureCall(payload);
}

/// The Liquid/LFM2.5 shape (measured 2026-10-09): a function-signature
/// call — `[get_weather(city="Tokyo")]` or
/// `get_weather(city="Tokyo", unit="celsius")`. Values are quoted
/// strings, numbers, or True/False/None.
_ToolCall? _parseSignatureCall(final String payload) {
  var body = payload.trim();
  // The measured Liquid shape wraps the call in a list: [name(args)].
  if (body.startsWith('[') && body.endsWith(']')) {
    body = body.substring(1, body.length - 1).trim();
  }
  final head = RegExp(r'([A-Za-z0-9_]+)\s*\(([\s\S]*)\)\s*$').firstMatch(body);
  if (head == null) return null;
  final args = <String, dynamic>{};
  final pair = RegExp(
    r'''([A-Za-z0-9_]+)\s*=\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|True|False|None)''',
  );
  for (final m in pair.allMatches(head.group(2)!)) {
    final rawValue = m.group(2)!;
    Object? value;
    if (rawValue.startsWith('"') || rawValue.startsWith("'")) {
      value = rawValue.substring(1, rawValue.length - 1);
    } else if (rawValue == 'True' || rawValue == 'False') {
      value = rawValue == 'True';
    } else if (rawValue == 'None') {
      value = null;
    } else {
      value = num.tryParse(rawValue) ?? rawValue;
    }
    args[m.group(1)!] = value;
  }
  return _ToolCall(head.group(1)!, args);
}

/// JSON, then a python-repr normalisation (Liquid models may emit
/// single-quoted dicts: `{'name': 'x', 'arguments': {'k': 'v'}}`).
Iterable<String> _jsonCandidates(final String payload) sync* {
  yield payload;
  yield payload.replaceAll("'", '"');
}

/// Last resort: a name-shaped `"name": "x"` / `'name': 'x'` anywhere in
/// the payload, no argument extraction.
_ToolCall? _scanCallName(final String payload) {
  final m =
      RegExp(r'''["']name["']\s*:\s*["']([A-Za-z0-9_]+)["']''').firstMatch(
    payload,
  );
  return m == null ? null : _ToolCall(m.group(1)!, const {});
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

/// The laya decision lane: the golden fixture (16 rows) through the
/// native decision engine — per-question argmax agreement vs the pinned
/// expectations, and per-row wall time. The numeric-parity gate
/// (distributions to 0.02) lives in test/laya_native_golden_test.dart;
/// this lane measures the model the way a cast uses it.
Future<_LaneResult> _runLaya() async {
  final fixtureFile = File('test/fixtures/laya_golden_fp16.json');
  if (!fixtureFile.existsSync()) {
    stderr.writeln('laya golden fixture absent — skipping');
    return _LaneResult('laya-decision', const []);
  }
  final NativeLayaDecisionEngine engine;
  try {
    engine = await NativeLayaDecisionEngine.load();
  } on Object catch (error) {
    stderr.writeln('native laya engine unavailable: $error — skipping');
    return _LaneResult('laya-decision', const []);
  }
  try {
    final cases = jsonDecode(fixtureFile.readAsStringSync()) as List;
    final results = <_CaseResult>[];
    for (final rawCase in cases) {
      final golden = rawCase as Map<String, dynamic>;
      final state = golden['state'];
      final t0 = DateTime.now();
      final decisions = engine.decideTyped(
        state: state is String ? state : renderLayaJson(state),
        questions: {
          for (final entry in (golden['questions'] as Map)
              .entries
              .cast<MapEntry<String, dynamic>>())
            entry.key: _layaQuestion(entry.value as Map<String, dynamic>),
        },
      );
      final wall = DateTime.now().difference(t0).inMilliseconds.toDouble();
      final answers = golden['answers'] as Map<String, dynamic>;
      final reasons = <String>[];
      for (final entry in answers.entries) {
        final expected = entry.value as Map<String, dynamic>;
        final actual = decisions[entry.key];
        if (actual == null) {
          reasons.add('${entry.key}: no decision returned');
          continue;
        }
        if (expected['type'] == 'choice' &&
            expected['choice'] != actual.choice) {
          reasons.add('${entry.key}: ${actual.choice} != ${expected['choice']}');
        }
      }
      results.add(_CaseResult(
        id: 'row${results.length}',
        ok: reasons.isEmpty,
        wallMs: wall,
        tokS: 0,
        reason: reasons.isEmpty ? null : reasons.join('; '),
      ));
    }
    return _LaneResult('laya-decision', results);
  } finally {
    engine.dispose();
  }
}

LayaTypedQuestion _layaQuestion(final Map<String, dynamic> definition) {
  final type = definition['type'] as String;
  final instructions = definition['instructions'];
  final instructionText =
      instructions is String ? instructions : renderLayaJson(instructions);
  switch (type) {
    case 'choice':
      final crit = definition['criteria'];
      return LayaTypedQuestion.choice(instructionText, {
        if (crit is Map)
          for (final entry in crit.entries.cast<MapEntry<dynamic, dynamic>>())
            '${entry.key}': renderLayaCriterion(
              entry.value == null || entry.value == '' ? '' : entry.value,
            )
        else
          for (final label in crit as List) '$label': '',
      });
    case 'score':
      return LayaTypedQuestion.score(instructionText, [
        for (final level in definition['criteria'] as List)
          renderLayaCriterion(level),
      ]);
    case 'noul':
      final crit = definition['criteria'];
      return LayaTypedQuestion.noul(
        instructionText,
        crit is Map
            ? {
                for (final entry
                    in crit.entries.cast<MapEntry<dynamic, dynamic>>())
                  '${entry.key}': entry.value == null
                      ? ''
                      : renderLayaCriterion(entry.value),
              }
            : null,
      );
    default:
      throw StateError('unknown laya question type $type');
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
