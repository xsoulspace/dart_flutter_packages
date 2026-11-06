/// P-2 scorer CLI — the `--scorer-cli` glue for `tool/runs/p2_runner.py`
/// (closes the NAMED gap SCORER_CLI_MISSING).
///
/// CONTRACT (p2_runner.py delegation contract, FROZEN there): invoked as
/// `/bin/zsh -lc <cmd>` with environment
///   WM_SCORED_INPUT  jsonl rows {suite, problem_id, sample_index,
///                    output_text, output_tokens, hit_token_limit}
///   WM_GOLD          the suite jsonl (p2-suite/v1 rows: {id, problem|question,
///                    answer?} + `specs` for the IFEval subset)
///   WM_SUITE         math500 | gsm8k_test | ifeval_subset
///   WM_OUT_JSON      output path; this tool writes
///                    {"suite", "accuracy" (PERCENT 0-100, published units),
///                     "n_problems", "n_samples_correct_over", ...}
/// Optional WM_CAP (int): when present, the frozen [tokenLimitRate] is also
/// computed over the scored rows and embedded (direct-cell convenience; the
/// runner ignores extra keys and computes its own hit stats from gens).
///
/// ORACLE LAW: the scoring itself is the FROZEN `lib/src/scorers.dart`
/// ([mathScore] / [gsm8kScore] / [ifevalChecks] / [tokenLimitRate]) — never
/// re-implemented here (a Python re-scoring inside the runner would be a
/// second, unfrozen oracle; that is why the runner refuses SCORER_CLI_MISSING
/// and delegates here).
///
/// SCORING-INPUT MAPPING: imported VERBATIM from `tool/runs/a2_score.dart`
/// (its documented "SCORING INPUT MAPPING" block, which mirrors the published
/// exp8 grading convention):
///   math/gsm8k : [a2.answerAfterThink] — text after the LAST `</think>` when
///                present, else the full output — then the frozen scorer
///                against the gold answer.
///   ifeval     : [a2.answerAfterThink] with `emptyWhenMissing: true` (with
///                thinking-on and NO `</think>` the answer is EMPTY -> every
///                check fails; exp8 grade_other convention), then the frozen
///                [ifevalChecks] over [a2.parseSpecs]-mapped gold specs.
///   tokenlimit : frozen [tokenLimitRate](output_tokens, cap) when WM_CAP set.
/// a2_score.dart does NOT itself satisfy the runner contract (it is an
/// argv-driven positional-gold scorer over generator files with prompt text;
/// the runner contract is env-driven, id-keyed gold, percent-accuracy JSON
/// out), so this file is the thin env/IO wrapper around the SAME imported
/// mapping functions and the SAME frozen scorers.
///
/// Accuracy convention (published units): mean over SAMPLE rows x 100
/// ("accuracy %, mean over samples" — exp8_math/eval/RESULTS_excerpt.md via
/// p2_runner.py PUBLISHED_CITATION). Empty-answer rows are counted and
/// surfaced (A2 NAMED gap EMPTY_ANSWER_LENIENT_ROWS) — never silently folded.
///
/// Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
///   0  ok (WM_OUT_JSON written)
///   2  named refusal: `ENV_MISSING:<name>`, SUITE_UNKNOWN, SUITE_ROW_MISMATCH,
///      SCORED_INPUT_UNREADABLE, SCORED_ROW_MALFORMED, GOLD_UNREADABLE,
///      `GOLD_ROW_MISSING:<id>`, `GOLD_ANSWER_MISSING:<id>`,
///      `GOLD_SPECS_MISSING:<id>`, EMPTY_SCORE_SAMPLE, CAP_INVALID,
///      OUT_WRITE_FAILED
///   1  INTERNAL (unexpected exception; message on stderr)
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_weightmap/src/scorers.dart';

// The A2 mapping of record: answerAfterThink / parseSpecs / wilson95 are
// imported, not copied (citation: tool/runs/a2_score.dart SCORING INPUT
// MAPPING block; itself mirroring exp8 grading).
import 'a2_score.dart' as a2;

const _knownSuites = {'math500', 'gsm8k_test', 'ifeval_subset'};

Never refuse(String code, String detail) {
  stderr.writeln('$code: $detail');
  exit(2);
}

String requireEnv(Map<String, String> env, String name) {
  final v = env[name];
  if (v == null || v.isEmpty) refuse('ENV_MISSING', name);
  return v;
}

List<Map<String, dynamic>> readJsonl(String path, String code) {
  final f = File(path);
  if (!f.existsSync()) refuse(code, 'file not found: $path');
  final rows = <Map<String, dynamic>>[];
  try {
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final j = jsonDecode(line);
      if (j is! Map<String, dynamic>) {
        refuse(code, 'row is not a json object: $path');
      }
      rows.add(j);
    }
  } on FormatException catch (e) {
    refuse(code, '$path (${e.message})');
  } on FileSystemException catch (e) {
    refuse(code, '$path (${e.message})');
  }
  return rows;
}

void main(List<String> argv) {
  final env = Platform.environment;
  final suite = requireEnv(env, 'WM_SUITE');
  final scoredPath = requireEnv(env, 'WM_SCORED_INPUT');
  final goldPath = requireEnv(env, 'WM_GOLD');
  final outPath = requireEnv(env, 'WM_OUT_JSON');
  if (!_knownSuites.contains(suite)) {
    refuse('SUITE_UNKNOWN', '$suite (known: ${_knownSuites.toList()})');
  }
  int? cap;
  final capRaw = env['WM_CAP'];
  if (capRaw != null && capRaw.isNotEmpty) {
    cap = int.tryParse(capRaw);
    if (cap == null || cap <= 0) refuse('CAP_INVALID', capRaw);
  }

  // Gold rows keyed by id (p2-suite/v1: {id, problem|question, answer?,
  // specs?}). Id-keyed (not positional): the runner's scored rows carry
  // problem_id and samples repeat problems.
  final gold = <String, Map<String, dynamic>>{};
  for (final g in readJsonl(goldPath, 'GOLD_UNREADABLE')) {
    final id = g['id'];
    if (id is! String || id.isEmpty) {
      refuse('GOLD_UNREADABLE', '$goldPath row without str id');
    }
    gold[id] = g;
  }

  final scored = readJsonl(scoredPath, 'SCORED_INPUT_UNREADABLE');
  if (scored.isEmpty) {
    refuse('EMPTY_SCORE_SAMPLE', '$scoredPath has no rows (accuracy with no '
        'denominator is undefined, not 0)');
  }

  var k = 0;
  var emptyAnswers = 0;
  var tokenSum = 0;
  var hitFlagCount = 0;
  final tokenCounts = <int>[];
  final problemIds = <String>{};
  final perProblem = <String, ({int correct, int over})>{};
  for (var i = 0; i < scored.length; i++) {
    final r = scored[i];
    final pid = r['problem_id'];
    final outText = r['output_text'];
    final outTok = r['output_tokens'];
    if (pid is! String || outText is! String || outTok is! int) {
      refuse(
        'SCORED_ROW_MALFORMED',
        '$scoredPath row $i: need str problem_id, str output_text, '
            'int output_tokens (got ${r.keys.toList()})',
      );
    }
    if (r['suite'] != null && r['suite'] != suite) {
      refuse('SUITE_ROW_MISMATCH', 'row $i suite ${r['suite']} != $suite');
    }
    final g = gold[pid];
    if (g == null) refuse('GOLD_ROW_MISSING', pid);
    problemIds.add(pid);
    tokenSum += outTok;
    tokenCounts.add(outTok);
    if (r['hit_token_limit'] == true) hitFlagCount++;

    int score;
    if (suite == 'ifeval_subset') {
      final rawSpecs = g['specs'];
      if (rawSpecs is! List) refuse('GOLD_SPECS_MISSING', pid);
      final input = a2.answerAfterThink(outText, emptyWhenMissing: true);
      if (input.isEmpty) emptyAnswers++;
      score = ifevalChecks(a2.parseSpecs(rawSpecs), input).isEmpty ? 1 : 0;
    } else {
      final goldAnswer = g['answer'];
      if (goldAnswer is! String) refuse('GOLD_ANSWER_MISSING', pid);
      final input = a2.answerAfterThink(outText);
      score = suite == 'math500'
          ? mathScore(input, goldAnswer)
          : gsm8kScore(input, goldAnswer);
    }
    k += score;
    final prev = perProblem[pid] ?? (correct: 0, over: 0);
    perProblem[pid] = (correct: prev.correct + score, over: prev.over + 1);
  }

  final n = scored.length;
  final accuracy = 100.0 * k / n;
  final ci = a2.wilson95(k, n);

  Map<String, Object?>? tokenLimit;
  final capVal = cap;
  if (capVal != null) {
    final rate = tokenLimitRate(tokenCounts, capVal);
    tokenLimit = {
      'cap': capVal,
      'hits': tokenCounts.where((t) => t >= capVal).length,
      'rate': rate,
      'generator_flag_hits': hitFlagCount,
      'note': 'frozen tokenLimitRate(count >= cap); generator_flag_hits is '
          'the hit_token_limit flag count (agreement cross-check)',
    };
  }

  final out = <String, Object?>{
    'schema': 'p2-scorer-out/v1',
    'suite': suite,
    'accuracy': double.parse(accuracy.toStringAsFixed(4)),
    'n_problems': problemIds.length,
    'n_samples_correct_over': n,
    'n_samples_correct': k,
    'wilson95_percent': [
      double.parse((ci.lo * 100).toStringAsFixed(4)),
      double.parse((ci.hi * 100).toStringAsFixed(4)),
    ],
    'empty_answer_rows': suite == 'ifeval_subset' ? emptyAnswers : null,
    'mean_output_tokens': double.parse((tokenSum / n).toStringAsFixed(2)),
    'token_limit': tokenLimit,
    'per_problem': {
      for (final e in perProblem.entries)
        e.key: {'correct': e.value.correct, 'over': e.value.over},
    },
    'scorer': {
      'frozen_oracle': 'lib/src/scorers.dart (mathScore/gsm8kScore/'
          'ifevalChecks/tokenLimitRate; PREREG-A A4 frozen, never edited)',
      'mapping_citation': 'tool/runs/a2_score.dart SCORING INPUT MAPPING '
          '(imported verbatim: answerAfterThink/parseSpecs/wilson95)',
      'accuracy_convention': 'mean over sample rows x 100 (published units)',
    },
    'created_utc': DateTime.now().toUtc().toIso8601String(),
  };
  try {
    File(outPath).writeAsStringSync('${const JsonEncoder.withIndent('  ')
        .convert(out)}\n');
  } on FileSystemException catch (e) {
    refuse('OUT_WRITE_FAILED', '$outPath (${e.message})');
  }
  stdout.writeln(
    jsonEncode({
      'tool': 'p2_scorer_cli.dart',
      'suite': suite,
      'accuracy': out['accuracy'],
      'n_problems': problemIds.length,
      'n_samples_correct_over': n,
      'out': outPath,
    }),
  );
}
