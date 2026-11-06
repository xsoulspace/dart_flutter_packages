/// V-6 engine-axis certifier (this run owns it; frozen oracles untouched).
///
/// Runs the FROZEN `lib/src/cross_engine.dart`
/// [CrossEngineCertification.certify] over the two engines' generation jsonl
/// files for the bf16/chat/greedy cell on the R removal mirror, under the
/// REGISTERED V-6 TOLERANCE `Tolerance(abs: 0.084, rel: 0)` on the loop-rate
/// behavior_value (1 cell in 12 per loop-rate; ws2 edge-inclusive law;
/// token-identity 0 is NOT required for V-6 — the pre-run registration row in
/// receipts/V6-matrix.jsonl records the choice).
///
/// Bundle cells (per engine): `loop_rate_G2` ONLY (behavior_value = frozen
/// scorers.dart [tokenLimitRate] over the 12 G2 content-token counts, cap
/// 256). loop_rate_G0, per-cell token-id equality and cap-hit flips are
/// recorded as CONTEXT rows (observation, not verdict-driving): the
/// registered tolerance is calibrated to the 12-cell G2 rate (1/12 = 0.0833
/// <= 0.084); a G0 (10-cell) or cap-hit (0/1) delta is not.
///
/// PYTHON-FIRST LAW (frozen): the python_mlxlm bundle is the REFERENCE, the
/// rust bundle the CANDIDATE; certify assigns roles itself; every
/// disagreement attributes to the candidate.
///
/// Usage: dart run tool/runs/v6_certify_dart.dart PY_GENS.jsonl
///            RUST_GENS.jsonl OUT.json
/// Exit: 0 = ran, verdict is data; 1 = NAMED operational refusal.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

const double kAbsTolerance = 0.084; // REGISTERED V-6 tolerance (pre-run row)
const double kRelTolerance = 0.0;

Never refuse(String code, String detail) {
  stderr.writeln('$code: $detail');
  exit(1);
}

String shaOf(Object? o) => sha256.convert(utf8.encode(jsonEncode(o))).toString();

List<Map<String, dynamic>> readGens(String path) {
  final f = File(path);
  if (!f.existsSync()) refuse('GENS_FILE_UNREADABLE', 'missing $path');
  final rows = <Map<String, dynamic>>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    try {
      rows.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
    } on FormatException catch (e) {
      refuse('GENS_ROW_MALFORMED', '$path: ${e.message}');
    }
  }
  return rows;
}

class Batch {
  Batch({required this.cells, required this.meta});
  final Map<String, Map<String, dynamic>> cells; // prompt_id -> row
  final Map<String, dynamic>? meta;
}

Batch parse(String path) {
  final rows = readGens(path);
  final cells = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? meta;
  for (final r in rows) {
    for (final k in ['mirror', 'prompt_id', 'token_ids', 'text', 'tokens']) {
      if (!r.containsKey(k)) {
        refuse('GENS_ROW_MALFORMED', '$path missing key $k');
      }
    }
    final id = r['prompt_id'] as String;
    if (id == '__meta__') {
      meta = Map<String, dynamic>.from(r['evidence'] as Map);
      continue;
    }
    if (cells.containsKey(id)) refuse('GENS_ROW_MALFORMED', '$path dup $id');
    cells[id] = r;
  }
  if (cells.isEmpty) refuse('BATTERY_INCOMPLETE', '$path: no cell rows');
  return Batch(cells: cells, meta: meta);
}

void main(List<String> argv) {
  if (argv.length != 3) {
    refuse('ARGS_INVALID',
        'usage: v6_certify_dart.dart PY_GENS.jsonl RUST_GENS.jsonl OUT.json');
  }
  final py = parse(argv[0]);
  final rust = parse(argv[1]);

  // shared cell set (both batteries must cover the same frozen cells)
  final ids = py.cells.keys.toList()..sort();
  for (final id in ids) {
    if (!rust.cells.containsKey(id)) {
      refuse('BATTERY_INCOMPLETE', 'rust gens lack cell $id');
    }
  }
  for (final id in rust.cells.keys) {
    if (!py.cells.containsKey(id)) {
      refuse('BATTERY_INCOMPLETE', 'python gens lack cell $id');
    }
  }

  final counts = {'python_mlxlm': <String, List<int>>{}, 'rust': <String, List<int>>{}};
  final caps = <String, Map<String, int>>{'python_mlxlm': {}, 'rust': {}};
  var idsEqual = 0;
  final idMismatches = <Map<String, dynamic>>[];
  final capHitFlips = <Map<String, dynamic>>[];
  for (final id in ids) {
    final p = py.cells[id]!;
    final r = rust.cells[id]!;
    final pEv = Map<String, dynamic>.from(p['evidence'] as Map);
    final rEv = Map<String, dynamic>.from(r['evidence'] as Map);
    final pIds = (p['token_ids'] as List).cast<int>();
    final rIds = (r['token_ids'] as List).cast<int>();
    if (jsonEncode(pIds) == jsonEncode(rIds)) {
      idsEqual++;
    } else {
      var firstDiv = -1;
      final n = pIds.length < rIds.length ? pIds.length : rIds.length;
      for (var i = 0; i < n; i++) {
        if (pIds[i] != rIds[i]) { firstDiv = i; break; }
      }
      idMismatches.add({
        'prompt_id': id,
        'first_divergence_index': firstDiv,
        'ids_sha256_py': shaOf(pIds),
        'ids_sha256_rust': shaOf(rIds),
      });
    }
    if (pEv['cap_hit'] != rEv['cap_hit']) {
      capHitFlips.add({
        'prompt_id': id,
        'cap_hit_py': pEv['cap_hit'],
        'cap_hit_rust': rEv['cap_hit'],
        'content_py': pEv['content_tokens'],
        'content_rust': rEv['content_tokens'],
      });
    }
    for (final spec in [('python_mlxlm', pEv), ('rust', rEv)]) {
      final g = spec.$2['group'] as String;
      (counts[spec.$1]![g] ??= <int>[]).add(spec.$2['content_tokens'] as int);
      (caps[spec.$1]![g] ??= spec.$2['cap'] as int);
    }
  }

  // frozen loop rates (scorers.dart tokenLimitRate) + bundles
  final rates = <String, Map<String, double>>{};
  final bundles = <String, List<CellDigest>>{};
  for (final engine in ['python_mlxlm', 'rust']) {
    final perGroup = <String, double>{};
    final cellDigests = <CellDigest>[];
    for (final g in (counts[engine]!.keys.toList()..sort())) {
      final rate = tokenLimitRate(counts[engine]![g]!, caps[engine]![g]!);
      perGroup[g] = rate;
      if (g == 'G2') {
        final concat = ids
            .where((i) =>
                (engine == 'python_mlxlm' ? py.cells[i]! : rust.cells[i]!)
                    ['evidence']['group'] == 'G2')
            .map((i) => shaOf((engine == 'python_mlxlm' ? py.cells[i]! : rust.cells[i]!)['token_ids']))
            .join();
        cellDigests.add(CellDigest(
          cell: 'loop_rate_G2',
          logitsDigest: shaOf(concat),
          behaviorDigest: shaOf({'group': 'G2', 'rate': rate}),
          behaviorValue: rate,
        ));
      }
    }
    rates[engine] = perGroup;
    bundles[engine] = cellDigests;
  }
  if (bundles['python_mlxlm']!.isEmpty || bundles['rust']!.isEmpty) {
    refuse('BATTERY_INCOMPLETE', 'no G2 group in one of the batches');
  }

  final verdict = CrossEngineCertification.certify(
    a: DigestBundle(engine: CrossEngine.pythonMlxlm, cells: bundles['python_mlxlm']!),
    b: DigestBundle(engine: CrossEngine.rust, cells: bundles['rust']!),
    tolerance: Tolerance(abs: kAbsTolerance, rel: kRelTolerance),
  );

  final out = {
    'tool': 'v6_certify_dart.dart',
    'created_utc': DateTime.now().toUtc().toIso8601String(),
    'axis': 'engine (ENGINE_REV; cell bf16__chat__greedy__rust vs '
        'bf16__chat__greedy__python-mlx-lm)',
    'tolerance': {'abs': kAbsTolerance, 'rel': kRelTolerance},
    'tolerance_registration': 'receipts/V6-matrix.jsonl seq 0 (pre-run): '
        '1 cell in 12 per loop-rate on the G2 behavior_value; token-identity '
        '0 NOT required; loop_rate_G2-only bundle (G0/cap-hit = context)',
    'loop_rate_py': rates['python_mlxlm'],
    'loop_rate_rust': rates['rust'],
    'certify': verdict.toJson(),
    'context': {
      'cells_compared_token_identity': ids.length,
      'token_id_pairs_equal': idsEqual,
      'token_id_mismatches': idMismatches,
      'cap_hit_flips': capHitFlips,
      'ws2_context': 'WS-2 measured 27/66 token-id equal across 3 mirrors; '
          'plant_1_removal (this mirror) 12/22 equal, loop_rate_G2 AGREE '
          '0.3333 = 0.3333 at Tolerance abs:0 (rates-only)',
    },
    'batch_meta': {'python_mlxlm': py.meta, 'rust': rust.meta},
    'non_claims': [
      'wall_ms/tok_s rows are non-claims (contention + POWER.md law)',
      'LOGITS_DIGEST_NOT_CAPTURED: token-id sequence digests key these '
          'bundles (WS-2 convention)',
    ],
  };
  File(argv[2]).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(out)}\n');
  stdout.writeln('V6_ENGINE_CERTIFY_DONE verdict=${verdict.label} '
      'loop_rate_G2 py=${rates['python_mlxlm']!['G2']} '
      'rust=${rates['rust']!['G2']} ids_equal=$idsEqual/${ids.length} '
      '-> ${argv[2]}');
  exit(0);
}
