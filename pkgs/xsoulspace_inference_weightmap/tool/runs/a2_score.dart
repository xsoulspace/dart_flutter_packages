/// A2-LOCAL scorer bin (PREREG-A arm A2, addendum 2026-11-05).
///
/// Reads generation JSONL rows written by mlx_native's frozen boundary script
/// `wm_qwen35_generate.py` plus positionally-aligned gold JSONL rows, scores
/// them with the FROZEN scorers in `lib/src/scorers.dart` (never modified
/// here), and emits a score JSONL: one row line per prompt plus a final
/// `{"kind":"summary",...}` line with k/n, score, Wilson 95% CI and (when
/// `--pub-acc`/`--pub-n` are given) the published-comparison flags.
///
/// SCORING INPUT MAPPING (documented A2-local harness decision, mirrors the
/// published exp8 grading convention — the frozen scorers themselves are
/// untouched):
///   math/gsm8k : text after the LAST `</think>` when present (mathqa.answer_text
///                "stray reasoning block cut off"), else the full output.
///   ifeval     : text after the last `</think>`; with thinking-on and NO
///                `</think>` the answer is EMPTY -> every check fails
///                (exp8 grade_other convention).
///   tokenlimit : frozen tokenLimitRate(output_tokens, cap) over all rows.
///
/// Usage (from the package directory):
///   dart run tool/runs/a2_score.dart --cell math|gsm8k|ifeval|tokenlimit
///       --config base|edited --cap N --gold gold.jsonl
///       --gen gen1.jsonl[,gen2.jsonl,...] --out scores.jsonl
///       [--n-rows K] [--pub-acc P --pub-n N]
///
/// `--gen` accepts comma-separated chunk files; rows are taken in file order
/// and MUST match the gold rows positionally (exact prompt-string equality is
/// asserted per row — misalignment is a named refusal, never a silent shift).
/// `--n-rows K` scores only the first K paired rows (PARTIAL denominators).
///
/// Exit codes: 0 OK; 2 NAMED refusal on stderr (ARGS_INVALID, CELL_UNKNOWN,
/// SPEC_UNKNOWN, GEN_MISSING, GOLD_MISSING, ALIGNMENT_MISMATCH_<i>,
/// ROW_COUNT_MISMATCH, PROMPT_ID_RESET_INVALID, OUT_WRITE_FAILED,
/// EMPTY_SCORE_SAMPLE, WILSON_UNDEFINED); 1 INTERNAL.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:xsoulspace_inference_weightmap/src/scorers.dart';

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested with 20 hand-scored rows in test/a2_score_test.dart)
// ---------------------------------------------------------------------------

/// The text the frozen scorers read: everything after the LAST `</think>`
/// (stripped) when the marker is present; otherwise the full [output] — or
/// the empty string when [emptyWhenMissing] (IFEval thinking-on convention).
String answerAfterThink(String output, {bool emptyWhenMissing = false}) {
  const marker = '</think>';
  final i = output.lastIndexOf(marker);
  if (i >= 0) return output.substring(i + marker.length).trim();
  return emptyWhenMissing ? '' : output;
}

/// Parses the gold-file spec vocabulary (written by the A2 prompt builder)
/// into frozen [IfevalSpec] instances. Unknown `t` = named refusal.
List<IfevalSpec> parseSpecs(List<dynamic> raw) {
  final specs = <IfevalSpec>[];
  for (final item in raw) {
    final m = item as Map<String, dynamic>;
    switch (m['t'] as String) {
      case 'word_count':
        specs.add(
          WordCountBound(
            minWords: m['min'] as int?,
            maxWords: m['max'] as int?,
          ),
        );
      case 'kw_include':
        specs.add(KeywordInclude((m['kw'] as List).cast<String>()));
      case 'kw_exclude':
        specs.add(KeywordExclude((m['kw'] as List).cast<String>()));
      case 'json_only':
        specs.add(const JsonOnlyOutput());
      case 'bullet_list':
        specs.add(BulletListFormat(minItems: (m['min_items'] as int?) ?? 1));
      case 'starts_with':
        specs.add(StartsWithPrefix(m['prefix'] as String));
      case 'upper_title':
        specs.add(const UppercaseTitleLine());
      default:
        throw FormatException('SPEC_UNKNOWN: t=${m['t']}');
    }
  }
  return specs;
}

/// Wilson score 95% interval for k successes in n trials (z = 1.959964).
({double lo, double hi}) wilson95(int k, int n) {
  if (n <= 0) {
    throw ArgumentError('WILSON_UNDEFINED: n must be > 0 (got $n)');
  }
  if (k < 0 || k > n) {
    throw ArgumentError('WILSON_UNDEFINED: k=$k outside [0, $n]');
  }
  const z = 1.959963984540054;
  final phat = k / n;
  final denom = 1 + z * z / n;
  final center = phat + z * z / (2 * n);
  final margin =
      z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n));
  return (
    lo: math.max(0.0, (center - margin) / denom),
    hi: math.min(1.0, (center + margin) / denom),
  );
}

/// One parsed generation row (wm_qwen35_generate.py output schema).
typedef GenRow = ({
  int promptId,
  String prompt,
  String outputText,
  int outputTokens,
  bool hitTokenLimit,
  String? finishReason,
  double wallMs,
});

GenRow parseGenRow(Map<String, dynamic> j) {
  return (
    promptId: j['prompt_id'] as int,
    prompt: j['prompt'] as String,
    outputText: j['output_text'] as String,
    outputTokens: j['output_tokens'] as int,
    hitTokenLimit: j['hit_token_limit'] as bool,
    finishReason: j['finish_reason'] as String?,
    wallMs: (j['wall_ms'] as num).toDouble(),
  );
}

/// Score one row for a 0/1 cell. Returns (score, detail-json fragment).
({int score, Map<String, Object?> detail}) scoreOneRow(
  String cell,
  GenRow row,
  Map<String, dynamic>? gold,
) {
  switch (cell) {
    case 'math':
    case 'gsm8k':
      final input = answerAfterThink(row.outputText);
      final goldAnswer = gold!['gold'] as String;
      final s = cell == 'math'
          ? mathScore(input, goldAnswer)
          : gsm8kScore(input, goldAnswer);
      return (
        score: s,
        detail: {'pred': extractFinalAnswer(input), 'gold': goldAnswer},
      );
    case 'ifeval':
      final input = answerAfterThink(row.outputText, emptyWhenMissing: true);
      final specs = parseSpecs((gold!['specs'] as List).cast<dynamic>());
      final failures = ifevalChecks(specs, input);
      return (
        score: failures.isEmpty ? 1 : 0,
        detail: {
          'fails': [
            for (final f in failures) {'check': f.check, 'detail': f.detail},
          ],
          'answer_empty': input.isEmpty,
        },
      );
    default:
      throw FormatException('CELL_UNKNOWN: $cell');
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

Never refuse(String code, String message) {
  stderr.writeln('$code: $message');
  exit(2);
}

Map<String, String> parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) refuse('ARGS_INVALID', 'expected --flag, got $a');
    final key = a.substring(2);
    if (i + 1 >= argv.length) refuse('ARGS_INVALID', 'missing value for $a');
    out[key] = argv[++i];
  }
  for (final req in ['cell', 'config', 'gen', 'out']) {
    if (!out.containsKey(req)) refuse('ARGS_INVALID', 'missing --$req');
  }
  return out;
}

List<Map<String, dynamic>> readJsonl(String path, String missingCode) {
  final f = File(path);
  if (!f.existsSync()) refuse(missingCode, 'file not found: $path');
  final rows = <Map<String, dynamic>>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    rows.add(jsonDecode(line) as Map<String, dynamic>);
  }
  return rows;
}

void main(List<String> argv) {
  final args = parseArgs(argv);
  final cell = args['cell']!;
  final config = args['config']!;
  if (!['math', 'gsm8k', 'ifeval', 'tokenlimit'].contains(cell)) {
    refuse('CELL_UNKNOWN', cell);
  }
  final cap = int.tryParse(args['cap'] ?? '');
  final genFiles = args['gen']!.split(',');
  final goldPath = args['gold'];
  final nRowsArg = int.tryParse(args['n-rows'] ?? '');

  // Concatenate chunk files in order; each file's prompt_id must restart at 0.
  final gen = <GenRow>[];
  for (final gf in genFiles) {
    final rows = readJsonl(gf, 'GEN_MISSING').map(parseGenRow).toList();
    for (var j = 0; j < rows.length; j++) {
      if (rows[j].promptId != j) {
        refuse(
          'PROMPT_ID_RESET_INVALID',
          '$gf row $j has prompt_id ${rows[j].promptId} (expected $j)',
        );
      }
    }
    gen.addAll(rows);
  }
  if (gen.isEmpty) refuse('EMPTY_SCORE_SAMPLE', 'no generation rows');

  List<Map<String, dynamic>>? gold;
  if (goldPath != null) gold = readJsonl(goldPath, 'GOLD_MISSING');

  var n = gen.length;
  if (gold != null) {
    if (nRowsArg != null) {
      n = math.min(nRowsArg, math.min(n, gold.length));
    } else if (n != gold.length) {
      refuse(
        'ROW_COUNT_MISMATCH',
        'gen rows ${gen.length} != gold rows ${gold.length} '
        '(pass --n-rows for a PARTIAL paired prefix)',
      );
    }
  } else if (nRowsArg != null) {
    n = math.min(nRowsArg, n);
  }
  if (cell == 'tokenlimit' && cap == null) {
    refuse('ARGS_INVALID', 'tokenlimit cell requires --cap');
  }

  final outLines = <String>[];
  var k = 0;
  var emptyAnswers = 0;
  var sumWall = 0.0;
  var sumTokens = 0;
  var flagAgree = 0;
  final tokenCounts = <int>[];
  for (var i = 0; i < n; i++) {
    final row = gen[i];
    final g = gold == null ? null : gold[i];
    if (g != null && g['prompt'] != row.prompt) {
      refuse('ALIGNMENT_MISMATCH_$i', 'gen prompt != gold prompt');
    }
    sumWall += row.wallMs;
    sumTokens += row.outputTokens;
    tokenCounts.add(row.outputTokens);
    if (row.hitTokenLimit == (cap != null && row.outputTokens >= cap)) {
      flagAgree++;
    }
    final Map<String, Object?> line = {
      'i': i,
      'cell': cell,
      'config': config,
      'out_tok': row.outputTokens,
      'hit': row.hitTokenLimit,
      'finish': row.finishReason,
      'wall_ms': row.wallMs,
    };
    if (cell == 'tokenlimit') {
      line['hit_at_cap'] = row.outputTokens >= cap!;
    } else {
      final r = scoreOneRow(cell, row, g);
      k += r.score;
      if (cell == 'ifeval' && r.detail['answer_empty'] == true) emptyAnswers++;
      line['score'] = r.score;
      line.addAll(r.detail);
    }
    outLines.add(jsonEncode(line));
  }

  final summary = <String, Object?>{
    'kind': 'summary',
    'cell': cell,
    'config': config,
    'cap': cap,
    'n': n,
    'mean_out_tok': sumTokens / n,
    'sum_wall_ms': sumWall.roundToDouble(),
    'hit_flag_agreement': '$flagAgree/$n',
  };
  if (cell == 'tokenlimit') {
    final rate = tokenLimitRate(tokenCounts.sublist(0, n), cap!);
    final hits = (rate * n).round();
    final ci = wilson95(hits, n);
    summary.addAll({
      'cap_hits': hits,
      'rate': rate,
      'wilson_lo': ci.lo,
      'wilson_hi': ci.hi,
    });
  } else {
    if (n == 0) refuse('EMPTY_SCORE_SAMPLE', 'n=0');
    final ci = wilson95(k, n);
    summary.addAll({
      'k': k,
      'score': k / n,
      'wilson_lo': ci.lo,
      'wilson_hi': ci.hi,
    });
    if (cell == 'ifeval') {
      // Frozen-scorer leniency note: an EMPTY answer (thinking-on, capped
      // before <think>) passes a spec set whose checks are all
      // exclusion/max-only (kw_exclude, word_count max). exp8 gates each
      // instruction on bool(resp); the frozen ifevalScore does not. Recorded
      // so the empty-answer count is never silently folded into the score.
      summary['empty_answer_rows'] = emptyAnswers;
    }
  }
  final pubAcc = double.tryParse(args['pub-acc'] ?? '');
  final pubN = int.tryParse(args['pub-n'] ?? '');
  if (pubAcc != null && pubN != null) {
    final pubCi = wilson95((pubAcc * pubN).round(), pubN);
    final ours = cell == 'tokenlimit'
        ? (summary['rate']! as double)
        : (summary['score']! as double);
    summary.addAll({
      'pub_acc': pubAcc,
      'pub_n': pubN,
      'pub_wilson_lo': pubCi.lo,
      'pub_wilson_hi': pubCi.hi,
      'our_point_in_pub_ci': ours >= pubCi.lo && ours <= pubCi.hi,
      'pub_point_in_our_ci': pubAcc >= (cell == 'tokenlimit'
          ? wilson95((ours * n).round(), n).lo
          : wilson95(k, n).lo) &&
          pubAcc <= wilson95(
            cell == 'tokenlimit' ? (ours * n).round() : k,
            n,
          ).hi,
    });
  }
  outLines.add(jsonEncode(summary));

  try {
    File(args['out']!).writeAsStringSync('${outLines.join('\n')}\n');
  } on IOException catch (e) {
    refuse('OUT_WRITE_FAILED', '${args['out']}: $e');
  }
  stdout.writeln(jsonEncode(summary));
}
