// g3_score.dart - G-3 pilot scorer/verdictor (PREREG-G §4-§6, FROZEN
// 2026-11-07). CPU-only: reads the runner's gens/arm_<X>.jsonl +
// arm_receipt_<X>.json + manifest.jsonl under --state, scores every arm with
// the FROZEN lib scorers (run, never edited), applies the frozen precondition
// / movement / guard / kill rules, and appends hash-chained verdict rows to
// receipts/G3-run.jsonl (+ a human summary at --summary).
//
// The offline loop-signature detector below is the Dart twin of the runner's
// frozen detector (PREREG-G §3); both are pinned by the SAME hand-computed
// golden vectors in tool/runs/g3_detector_golden.json (a golden mismatch is a
// named refusal, never a fix-in-place).
//
// NO CERTIFICATION FROM THE PILOT (§6.6): verdicts are instrument/movement
// facts; the certification shape belongs to stage 2.
//
// usage: dart run tool/runs/g3_score.dart --state <run-dir> \
//            --cells tool/runs/cells_frozen_A3.json \
//            --out receipts/G3-run.jsonl --summary receipts/G3-summary.md
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

// --- frozen constants (PREREG-G; mirror g3_revision.py) -------------------
const int detN = 4;
const int detWindow = 64;
const int detThreshold = 3;
const List<String> armsFrozen = ['R0', 'R1', 'R2', 'R3', 'NULLA'];
const String cellsShaFrozen =
    '8406130623b6e85922eac6cbd92b73dd2282e6fc19538bb3c199f647f518d760';
const int headroomFloor = 9; // §6.1: R0 cap-hit >= 9/12 else HEADROOM_REJECTED
const int movementCapCells = 4; // §6.2 clause 1: |Δ cap-hit cells| >= 4 of 12
const double movementLsRel = 0.25; // §6.2 clause 2: same-direction >= 25% rel
const int guardSlack = 1; // §6.3: G0 success < R0 − 1 => GUARDRAIL_FAIL

// --- FROZEN detector (§3; golden-pinned in test/g3_score_test.dart) ------
bool detectorFiresAt(List<int> ids) {
  final t1 = ids.length;
  if (t1 < detN) return false;
  final lo = math.max(0, t1 - detWindow);
  var cnt = 0;
  for (var i = lo; i <= t1 - detN; i++) {
    var eq = true;
    for (var j = 0; j < detN; j++) {
      if (ids[i + j] != ids[t1 - detN + j]) {
        eq = false;
        break;
      }
    }
    if (eq) {
      cnt++;
      if (cnt >= detThreshold) return true;
    }
  }
  return false;
}

List<int> loopTriggers(List<int> ids) => [
      for (var t = 0; t < ids.length; t++)
        if (detectorFiresAt(ids.sublist(0, t + 1))) t,
    ];

// --- A3-frozen cell scorers, copied VERBATIM from a3_score.dart (A4 freeze;
// --- attribution: same frozen text, scope law keeps runners standalone) ---
String thinkStrip(String o) {
  const openTag = '<think>';
  const closeTag = '</' 'think>';
  if (o.trimLeft().startsWith(openTag)) {
    final parts = o.split(closeTag);
    if (parts.length > 1) {
      return parts.sublist(1).join(closeTag);
    }
  }
  return o;
}

String? firstLine(String o) {
  for (final ln in o.split('\n')) {
    if (ln.trim().isNotEmpty) return ln.trim();
  }
  return null;
}

bool scoreCell(Map<String, Object?> cell, String output) {
  final scorer = cell['scorer']! as String;
  if (scorer == 'numeric_final') {
    return mathScore(thinkStrip(output), cell['gold']! as String) == 1;
  }
  final fl = firstLine(thinkStrip(output));
  if (fl == null) return false;
  final gold = cell['gold']! as String;
  if (scorer == 'label_first_line') return fl.toLowerCase() == gold.toLowerCase();
  if (scorer == 'string_first_line') {
    var s = fl;
    const quotes = '"\'`';
    if (s.length >= 2 && s[0] == s[s.length - 1] && quotes.contains(s[0])) {
      s = s.substring(1, s.length - 1);
    }
    if (!gold.endsWith('.') && s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s == gold;
  }
  throw StateError('SCORER_UNKNOWN: $scorer');
}

// --- metrics (pure; unit-tested) ------------------------------------------
final class ArmMetrics {
  ArmMetrics({
    required this.arm,
    required this.cellsScored,
    required this.duplicates,
    required this.inconsistentRows,
    required this.g2CapHit,
    required this.g2Total,
    required this.g2LsCells,
    required this.g0Pass,
    required this.g0Total,
    required this.medianTokensG2,
    required this.medianTokensG0,
    required this.interventions,
    required this.forwards,
  });
  final String arm;
  final int cellsScored;
  final int duplicates;
  final int inconsistentRows;
  final int g2CapHit;
  final int g2Total;
  final int g2LsCells; // cells with >= 1 offline trigger (G2)
  final int g0Pass;
  final int g0Total;
  final double medianTokensG2;
  final double medianTokensG0;
  final int interventions;
  final int forwards;
  double get g2CapHitRate => g2Total == 0 ? double.nan : g2CapHit / g2Total;
  double get g2LsRate => g2Total == 0 ? double.nan : g2LsCells / g2Total;

  // canonicalJson fails loudly on NaN (ledger law) — nulls, never NaN
  static Object? numOrNull(double v) => v.isNaN ? null : v;

  Map<String, Object?> toJson() => {
        'arm': arm,
        'cells_scored': cellsScored,
        'duplicate_rows_deduped': duplicates,
        'inconsistent_rows': inconsistentRows,
        'g2_cap_hit': '$g2CapHit/$g2Total',
        'g2_cap_hit_rate': numOrNull(tokenLimitRateCapRate),
        'g2_loop_signature_cells': g2LsCells,
        'g2_loop_signature_rate': numOrNull(g2LsRate),
        'g0_guard_pass': '$g0Pass/$g0Total',
        'median_tokens_g2': numOrNull(medianTokensG2),
        'median_tokens_g0': numOrNull(medianTokensG0),
        'interventions_total': interventions,
        'total_forward_tokens': forwards,
      };
  // primary cap-hit rate via the FROZEN scorer (run, never edited)
  double tokenLimitRateCapRate = double.nan;
}

double median(List<int> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2.0;
}

/// Scores one arm's cell rows against the frozen cell map. Rows are keyed by
/// cell_id (last-wins; duplicates counted). Row-internal consistency is
/// checked (cap_hit vs finish_reason/output_tokens; output_tokens vs
/// generated_ids length); an inconsistent row is NAMED and scored from the
/// raw fields, never silently trusted.
ArmMetrics scoreArmRows(
  String arm,
  List<Map<String, Object?>> rows,
  Map<String, Map<String, Object?>> cellsById,
) {
  final byCell = <String, Map<String, Object?>>{};
  var duplicates = 0;
  for (final r in rows) {
    final id = r['cell_id']! as String;
    if (byCell.containsKey(id)) duplicates++;
    byCell[id] = r;
  }
  var inconsistent = 0;
  final g2Tokens = <int>[];
  final g0Tokens = <int>[];
  var g2CapHit = 0;
  var g2Total = 0;
  var g2Ls = 0;
  var g0Pass = 0;
  var g0Total = 0;
  var interventions = 0;
  var forwards = 0;
  final capCounts = <int>[];
  var capForRate = 0;
  for (final entry in byCell.entries) {
    final cell = cellsById[entry.key];
    if (cell == null) {
      throw StateError('CELL_UNKNOWN: ${entry.key} (arm $arm)');
    }
    final r = entry.value;
    final ids = (r['generated_ids']! as List).cast<int>();
    final outTokens = r['output_tokens']! as int;
    final finish = r['finish_reason']! as String;
    final cap = cell['cap']! as int;
    if (outTokens != ids.length ||
        (r['cap_hit']! as bool) != (finish == 'length') ||
        (finish == 'length' && outTokens != cap)) {
      inconsistent++;
    }
    final capHit = finish == 'length'; // scored from raw fields (§4)
    final triggers = loopTriggers(ids);
    interventions += (r['interventions']! as List).length;
    forwards += (r['total_forward_tokens']! as int?) ?? 0;
    if (cell['group'] == 'G2') {
      g2Total++;
      g2Tokens.add(outTokens);
      capCounts.add(outTokens);
      capForRate = cap;
      if (capHit) g2CapHit++;
      if (triggers.isNotEmpty) g2Ls++;
    } else if (cell['group'] == 'G0') {
      g0Total++;
      g0Tokens.add(outTokens);
      if (scoreCell(cell, r['output']! as String)) g0Pass++;
    }
  }
  final m = ArmMetrics(
    arm: arm,
    cellsScored: byCell.length,
    duplicates: duplicates,
    inconsistentRows: inconsistent,
    g2CapHit: g2CapHit,
    g2Total: g2Total,
    g2LsCells: g2Ls,
    g0Pass: g0Pass,
    g0Total: g0Total,
    medianTokensG2: median(g2Tokens),
    medianTokensG0: median(g0Tokens),
    interventions: interventions,
    forwards: forwards,
  );
  if (capCounts.isNotEmpty) {
    m.tokenLimitRateCapRate = tokenLimitRate(capCounts, capForRate);
  }
  return m;
}

/// §6.2 MOVEMENT criterion (pure; both clauses required).
Map<String, Object?> movementRule(ArmMetrics rx, ArmMetrics r0) {
  final capDiffCells = (rx.g2CapHit - r0.g2CapHit).abs();
  final capDir = (rx.g2CapHit - r0.g2CapHit).sign;
  final lsDiff = rx.g2LsCells - r0.g2LsCells;
  final lsDir = lsDiff.sign;
  final clause1 = capDiffCells >= movementCapCells;
  String reason;
  var clause2 = false;
  if (r0.g2LsCells == 0) {
    reason = lsDiff == 0 ? 'LS_BASE_ZERO_NO_MOVEMENT' : 'LS_BASE_ZERO';
  } else {
    final rel = lsDiff.abs() / r0.g2LsCells;
    clause2 = rel >= movementLsRel && lsDir == capDir && lsDir != 0;
    reason = clause2
        ? 'BOTH_CLAUSES'
        : (capDir == 0 || lsDir == 0
            ? 'DIRECTION_ZERO'
            : (lsDir != capDir ? 'DIRECTION_MISMATCH' : 'LS_REL_BELOW_FLOOR'));
  }
  return {
    'arm': rx.arm,
    'moves': clause1 && clause2,
    'cap_hit_diff_cells': capDiffCells,
    'ls_cells_rx': rx.g2LsCells,
    'ls_cells_r0': r0.g2LsCells,
    'clause1_cap_diff_ge_$movementCapCells': clause1,
    'clause2_ls_same_direction_ge_${movementLsRel}rel': clause2,
    'reason': reason,
  };
}

/// §6.4 KILL RULE (pure). Full SAMPLER_GENERIC requires BOTH R2 and R3
/// within 1 cap-hit cell of a MOVING R1; an R2-blocked variant is named.
String? killRule(Map<String, ArmMetrics> m, Set<String> blocked,
    Map<String, bool> moves) {
  if (!moves.containsKey('R1') || !moves['R1']!) return null;
  final r1 = m['R1']!;
  bool within(String arm) =>
      m.containsKey(arm) && (m[arm]!.g2CapHit - r1.g2CapHit).abs() <= 1;
  final r3Ok = within('R3');
  if (within('R2') && r3Ok) return 'SAMPLER_GENERIC';
  if (blocked.contains('R2') && r3Ok) {
    return 'SAMPLER_GENERIC_PARTIAL_R2_BLOCKED';
  }
  return null;
}

/// §6.6 stage verdict (pure; precedence frozen).
String stageVerdict({
  required bool r0DeterminismReproduced, // false => drift
  required bool determinismRowPresent,
  required int r0G2CapHit,
  required bool r0Present,
  required Set<String> armsPresent,
  required Set<String> blocked,
  required String? kill,
}) {
  if (r0Present && determinismRowPresent && !r0DeterminismReproduced) {
    return 'INSTRUMENT_UNVALIDATED_DETERMINISM_DRIFT';
  }
  if (!r0Present) return 'PARTIAL_WITH_DENOMINATOR_R0_MISSING';
  if (r0G2CapHit < headroomFloor) return 'HEADROOM_REJECTED';
  if (kill != null) return kill;
  final missing = armsFrozen
      .where((a) => !armsPresent.contains(a) && !blocked.contains(a))
      .toList();
  if (missing.isNotEmpty) {
    return 'PARTIAL_WITH_DENOMINATOR_ARMS_MISSING(${missing.join(",")})';
  }
  return 'INSTRUMENT_VALIDATED';
}

// --- IO --------------------------------------------------------------------
Never refuse(String code, String message) {
  stderr.writeln('$code: $message');
  exit(1);
}

Map<String, String> parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length - 1; i += 2) {
    if (!argv[i].startsWith('--')) {
      refuse('ARGV_INVALID', 'expected --flag at position $i: ${argv[i]}');
    }
    out[argv[i].substring(2)] = argv[i + 1];
  }
  return out;
}

List<Map<String, Object?>> readJsonl(File f) => f
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => (jsonDecode(l) as Map).cast<String, Object?>())
    .toList();

String sha256File(String p) =>
    sha256.convert(File(p).readAsBytesSync()).toString();

void main(List<String> argv) {
  final args = parseArgs(argv);
  final state = args['state'];
  final cellsPath = args['cells'];
  final outPath = args['out'];
  final summaryPath = args['summary'];
  for (final e in {
    'state': state,
    'cells': cellsPath,
    'out': outPath,
    'summary': summaryPath
  }.entries) {
    if (e.value == null) refuse('ARGV_MISSING', '--${e.key}');
  }
  if (!Directory(state!).existsSync()) {
    refuse('STATE_MISSING', state);
  }
  if (!File(cellsPath!).existsSync()) refuse('CELLS_FILE_MISSING', cellsPath);
  final cellsDigest = sha256File(cellsPath);
  final expectSha = args['expect-cells-sha'] ?? cellsShaFrozen;
  if (cellsDigest != expectSha) {
    refuse('CELLS_DIGEST_DRIFT',
        '$cellsPath is $cellsDigest, expected $expectSha');
  }
  final cellsDoc =
      jsonDecode(File(cellsPath).readAsStringSync()) as Map<String, Object?>;
  final groups = (cellsDoc['cells']! as Map).cast<String, Object?>();
  final cellsById = <String, Map<String, Object?>>{};
  for (final c in (groups['G2']! as List).cast<Map<String, Object?>>()) {
    cellsById[c['id']! as String] = {...c, 'group': 'G2'};
  }
  final g0 = (groups['G0']! as List).cast<Map<String, Object?>>();
  for (final c in g0.sublist(0, math.min(8, g0.length))) {
    cellsById[c['id']! as String] = {...c, 'group': 'G0'};
  }

  // manifest: blocked/failed arm rows are verdict inputs (§6.5)
  final blocked = <String>{};
  final failed = <String>{};
  final manifestFile = File('$state/manifest.jsonl');
  if (manifestFile.existsSync()) {
    for (final r in readJsonl(manifestFile)) {
      final arm = r['arm'] as String?;
      if (arm == null) continue;
      if (r['kind'] == 'arm_blocked') blocked.add(arm);
      if (r['kind'] == 'arm_failed') failed.add(arm);
    }
  }

  final outFile = File(outPath!);
  append(outFile, 'g3_stage_start', {
    'stage': 'pilot',
    'prereg': 'PREREG-G.md FROZEN 2026-11-07 (stage 2: PREREG-G-STAGE2.md)',
    'cells': cellsPath,
    'cells_sha256': cellsDigest,
    'expect_cells_sha': expectSha,
    'state': state,
    'arms_expected': armsFrozen,
    'arms_blocked': blocked.toList()..sort(),
    'arms_failed': failed.toList()..sort(),
  });

  final metrics = <String, ArmMetrics>{};
  final determinism = <String, Object?>{};
  var determinismRowPresent = false;
  var determinismOk = true;
  for (final arm in armsFrozen) {
    final gensFile = File('$state/gens/arm_$arm.jsonl');
    final receiptFile = File('$state/arm_receipt_$arm.json');
    if (!gensFile.existsSync()) {
      append(outFile, 'g3_arm_missing', {
        'arm': arm,
        'blocked': blocked.contains(arm),
        'failed': failed.contains(arm),
        'reason': blocked.contains(arm)
            ? 'ARM_BLOCKED (PREREG-G §6.5; see manifest)'
            : 'ARM_FILE_MISSING (not run / not complete)',
      });
      continue;
    }
    final rows = readJsonl(gensFile);
    final m = scoreArmRows(arm, rows, cellsById);
    metrics[arm] = m;
    final payload = m.toJson();
    if (receiptFile.existsSync()) {
      final receipt = jsonDecode(receiptFile.readAsStringSync())
          as Map<String, Object?>;
      payload['arm_receipt'] = {
        'engine_rev': receipt['engine_rev'],
        'eos_ids': (receipt['tokenizer'] as Map?)?['eos_ids'],
        'render_cell0_sha256':
            (receipt['tokenizer'] as Map?)?['render_cell0_sha256'],
        'base_receipt': receipt['base_receipt'],
        'embed_path': receipt['embed_path'],
      };
      if (arm == 'R0' && receipt['determinism'] != null) {
        final d = (receipt['determinism']! as Map).cast<String, Object?>();
        determinismRowPresent = true;
        determinismOk = d['reproduced']! as bool;
        determinism.addAll(d);
      }
    }
    append(outFile, 'g3_arm_metrics', payload);
  }

  final r0 = metrics['R0'];
  append(outFile, 'g3_determinism', {
    'rule': 'PREREG-G §4 R0 re-run of first 4 G2 cells, exact reproduction',
    'row_present': determinismRowPresent,
    'reproduced': determinismRowPresent ? determinismOk : null,
    'detail': determinism,
    'consequence_on_drift': 'stage verdict capped at INSTRUMENT_UNVALIDATED',
  });
  append(outFile, 'g3_headroom_precondition', {
    'rule': 'PREREG-G §6.1: R0 G2 cap-hit >= $headroomFloor/12 else '
        'HEADROOM_REJECTED (saturation lesson applied prospectively)',
    'r0_g2_cap_hit': r0 == null ? null : '${r0.g2CapHit}/${r0.g2Total}',
    'status': r0 == null
        ? 'R0_MISSING'
        : (r0.g2CapHit >= headroomFloor ? 'OK' : 'HEADROOM_REJECTED'),
  });

  final moves = <String, bool>{};
  if (r0 != null) {
    for (final arm in armsFrozen.where((a) => a != 'R0')) {
      final m = metrics[arm];
      if (m == null) continue;
      final mv = movementRule(m, r0);
      moves[arm] = mv['moves']! as bool;
      mv['guard'] = (m.g0Pass < r0.g0Pass - guardSlack)
          ? 'GUARDRAIL_FAIL (§6.3: G0 ${m.g0Pass}/${m.g0Total} < R0 '
              '${r0.g0Pass}/${r0.g0Total} − $guardSlack)'
          : 'GUARD_OK';
      append(outFile, 'g3_movement', mv);
    }
  }
  final kill = r0 == null ? null : killRule(metrics, blocked, moves);
  append(outFile, 'g3_kill_rule', {
    'rule': 'PREREG-G §6.4: R1 moves AND R2,R3 within 1 cap-hit cell of R1 '
        '=> SAMPLER_GENERIC (a SUCCESSFUL cheap verdict)',
    'fires': kill,
  });
  final verdict = stageVerdict(
    r0DeterminismReproduced: determinismOk,
    determinismRowPresent: determinismRowPresent,
    r0G2CapHit: r0?.g2CapHit ?? 0,
    r0Present: r0 != null,
    armsPresent: metrics.keys.toSet(),
    blocked: blocked,
    kill: kill,
  );
  append(outFile, 'g3_stage_verdict', {
    'stage': 'pilot',
    'verdict': verdict,
    'non_claim': 'NO CERTIFICATION FROM THE PILOT (§6.6); solicited-loop '
        'cells: movement is mechanism evidence, never "fixed looping"',
    'denominator': {
      for (final m in metrics.values) m.arm: '${m.cellsScored} cells',
    },
  });
  final chain = verifyChain(outFile);
  final summary = StringBuffer()
    ..writeln('# G-3 pilot summary (PREREG-G, frozen 2026-11-07)')
    ..writeln()
    ..writeln('Stage verdict: **$verdict**')
    ..writeln('Chain: ${chain.label}')
    ..writeln()
    ..writeln('| arm | G2 cap-hit | G2 loop-sig | G0 guard | med tok G2 '
        '| interventions |')
    ..writeln('|---|---|---|---|---|---|');
  for (final arm in armsFrozen) {
    final m = metrics[arm];
    if (m == null) {
      final tag = blocked.contains(arm) ? 'BLOCKED' : 'missing';
      summary.writeln('| $arm | — | — | — | — | $tag |');
      continue;
    }
    summary.writeln('| $arm | ${m.g2CapHit}/${m.g2Total} '
        '(${(m.g2CapHitRate * 100).toStringAsFixed(1)}%) '
        '| ${m.g2LsCells}/${m.g2Total} '
        '| ${m.g0Pass}/${m.g0Total} | ${m.medianTokensG2} '
        '| ${m.interventions} |');
  }
  summary
    ..writeln()
    ..writeln('Kill rule: ${kill ?? "not fired"}; determinism row present: '
        '$determinismRowPresent (reproduced: $determinismOk).')
    ..writeln('Non-claims: absolute ms non-claims (POWER.md); wall_ms rows '
        'flagged; no transfer outside the §5 certification key; pilot '
        'certifies nothing (§6.6).');
  File(summaryPath!).writeAsStringSync(summary.toString());
  stdout.writeln(jsonEncode({
    'tool': 'g3_score.dart',
    'verdict': verdict,
    'kill': kill,
    'chain': chain.label,
    'out': outPath,
    'summary': summaryPath,
  }));
}
