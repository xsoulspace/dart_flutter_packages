/// WS-2 cross-engine agreement driver (PROGRAM.md Phase B): assembles the
/// frozen [DigestBundle]s from the two engines' generation jsonl files, runs
/// the per-cell token-id identity check (tolerance 0 on ids), and certifies
/// each mirror with the FROZEN `lib/src/cross_engine.dart`
/// [CrossEngineCertification.certify] under the pre-registered
/// `Tolerance(abs: 0, rel: 0)` (greedy determinism expects identical
/// per-mirror loop rates — frozen scorers.dart [tokenLimitRate]).
///
/// PYTHON-FIRST LAW: the python_mlxlm bundle is the reference, the rust
/// bundle the candidate; certify assigns the roles itself (argument order
/// irrelevant). Mismatches are NAMED per-cell findings — recorded, never
/// retried into agreement.
///
/// Bundle cells per mirror (24): the 22 frozen cells (behavior_value =
/// cap-hit indicator under the frozen count>=cap rule; logits_digest =
/// sha256 of the generated token-id sequence — NAMED non-capture:
/// LOGITS_DIGEST_NOT_CAPTURED, raw-logits digests are optional identity
/// evidence per the WS-2 task and token-id digests key these runs instead)
/// plus `loop_rate_G2` / `loop_rate_G0` (behavior_value = frozen
/// tokenLimitRate over that group's content-token counts and frozen cap).
///
/// Usage (from the package dir):
///   `dart run tool/runs/ws2_certify_dart.dart WORK_DIR OUT.jsonl
///       [--mirrors base,plant_1,plant_1_removal]`
///
/// WORK_DIR layout: prompts.json, `gen/py_MIRROR.jsonl`,
/// `gen/rust_MIRROR.jsonl`, optional rebuild_verification.jsonl and
/// lock_log.jsonl (copied through into the receipt as kind=rebuild/lock
/// rows). The out.jsonl receives: per mirror x prompt cell rows, finding
/// rows, per-mirror certify rows, batch-meta rows, one summary row.
///
/// Exit codes: 0 = the run COMPLETED and the truth was written (verdict
/// PASS or FAIL is data); 1 = NAMED operational refusal (missing file,
/// malformed row, engine contract violation).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

const List<String> kRequiredKeys = [
  'mirror',
  'prompt_id',
  'token_ids',
  'text',
  'tokens',
];

String shaOf(Object? o) =>
    sha256.convert(utf8.encode(jsonEncode(o))).toString();

Never refuse(String code, String detail) {
  stderr.writeln('$code: $detail');
  exit(1);
}

List<Map<String, dynamic>> readJsonl(String path, String code) {
  final f = File(path);
  if (!f.existsSync()) refuse(code, 'missing $path');
  final rows = <Map<String, dynamic>>[];
  for (final line in f.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    try {
      rows.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
    } on FormatException catch (e) {
      refuse(code, '$path: ${e.message}');
    }
  }
  return rows;
}

/// One engine's parsed batch for one mirror.
class EngineBatch {
  EngineBatch({required this.engine, required this.cells, this.meta});

  final CrossEngine engine;
  final Map<String, Map<String, dynamic>> cells; // prompt_id -> row
  final Map<String, dynamic>? meta;
}

EngineBatch parseBatch(
  String path,
  CrossEngine engine,
  String mirror,
  List<String> expectedIds,
) {
  final rows = readJsonl(path, 'BATCH_FILE_UNREADABLE');
  final cells = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? meta;
  for (final r in rows) {
    for (final k in kRequiredKeys) {
      if (!r.containsKey(k)) {
        refuse('BATCH_ROW_MALFORMED', '$path missing key $k');
      }
    }
    if (r['mirror'] != mirror) {
      refuse('BATCH_ROW_MALFORMED',
          '$path row mirror=${r['mirror']} expected $mirror');
    }
    final id = r['prompt_id'] as String;
    if (id == '__meta__') {
      meta = Map<String, dynamic>.from(r['evidence'] as Map);
      continue;
    }
    if (cells.containsKey(id)) refuse('BATCH_ROW_MALFORMED', '$path dup $id');
    cells[id] = r;
  }
  for (final id in expectedIds) {
    if (!cells.containsKey(id)) {
      refuse('BATCH_CELL_MISSING', '$path: cell $id absent (engine batch '
          'incomplete — a partial batch is a refusal, not a mismatch)');
    }
  }
  return EngineBatch(engine: engine, cells: cells, meta: meta);
}

void main(List<String> argv) {
  if (argv.length < 2) {
    refuse('ARGS_INVALID',
        'usage: ws2_certify_dart.dart <work-dir> <out.jsonl> [--mirrors a,b]');
  }
  final work = argv[0];
  final outPath = argv[1];
  var mirrors = ['base', 'plant_1', 'plant_1_removal'];
  final mi = argv.indexOf('--mirrors');
  if (mi >= 0 && mi + 1 < argv.length) {
    mirrors = argv[mi + 1].split(',').where((s) => s.isNotEmpty).toList();
  }

  final promptsFile = File('$work/prompts.json');
  if (!promptsFile.existsSync()) refuse('PROMPTS_FILE_UNREADABLE', work);
  final prompts =
      jsonDecode(promptsFile.readAsStringSync()) as Map<String, dynamic>;
  final promptCells = (prompts['cells'] as List)
      .map((c) => Map<String, dynamic>.from(c as Map))
      .toList();
  final ids = [for (final c in promptCells) c['prompt_id'] as String];
  final groupOf = {
    for (final c in promptCells) c['prompt_id'] as String: c['group'] as String,
  };
  final capOf = {
    for (final c in promptCells) c['prompt_id'] as String: c['cap'] as int,
  };
  // frozen caps come from the rendered cells (surface.caps applied at
  // render time, authoritative per cells_frozen_A3.json)
  final g2Cap = promptCells
      .firstWhere((c) => c['group'] == 'G2', orElse: () => {'cap': 256})['cap']
      as int;
  final g0Cap = promptCells
      .firstWhere((c) => c['group'] == 'G0', orElse: () => {'cap': 64})['cap']
      as int;

  final out = <Map<String, dynamic>>[];
  // pass-through evidence rows (rebuild digest gate + device-lock log)
  for (final spec in [
    ('rebuild', '$work/rebuild_verification.jsonl'),
    ('lock', '$work/lock_log.jsonl'),
  ]) {
    final f = File(spec.$2);
    if (f.existsSync()) {
      for (final r in readJsonl(spec.$2, 'PASSTHROUGH_UNREADABLE')) {
        out.add({'kind': spec.$1, ...r});
      }
    }
  }

  var idsEqualTotal = 0;
  var idsMismatchTotal = 0;
  final findings = <Map<String, dynamic>>[];
  final certifyRows = <Map<String, dynamic>>[];

  for (final mirror in mirrors) {
    final py = parseBatch('$work/gen/py_$mirror.jsonl',
        CrossEngine.pythonMlxlm, mirror, ids);
    final rust = parseBatch('$work/gen/rust_$mirror.jsonl',
        CrossEngine.rust, mirror, ids);
    for (final spec in [('python_mlxlm', py), ('rust', rust)]) {
      if (spec.$2.meta case final m?) {
        out.add({'kind': 'batch_meta', 'mirror': mirror, 'engine': spec.$1,
          ...m});
      }
    }

    final pyCounts = <String, List<int>>{'G0': [], 'G2': []};
    final rustCounts = <String, List<int>>{'G0': [], 'G2': []};
    final pyCells = <CellDigest>[];
    final rustCells = <CellDigest>[];

    for (final id in ids) {
      final p = py.cells[id]!;
      final r = rust.cells[id]!;
      final pyIds = (p['token_ids'] as List).cast<int>();
      final rustIds = (r['token_ids'] as List).cast<int>();
      final pEv = Map<String, dynamic>.from(p['evidence'] as Map);
      final rEv = Map<String, dynamic>.from(r['evidence'] as Map);
      final promptIdsEqual =
          jsonEncode(pEv['prompt_token_ids']) == jsonEncode(rEv['prompt_token_ids']);
      final idsEqual = jsonEncode(pyIds) == jsonEncode(rustIds);
      var firstDivergence = -1;
      if (!idsEqual) {
        final n = pyIds.length < rustIds.length ? pyIds.length : rustIds.length;
        firstDivergence = pyIds.length == rustIds.length
            ? -2 // same length, differ in value (loop below finds it)
            : n;
        for (var i = 0; i < n; i++) {
          if (pyIds[i] != rustIds[i]) {
            firstDivergence = i;
            break;
          }
        }
      }
      if (idsEqual) {
        idsEqualTotal++;
      } else {
        idsMismatchTotal++;
        final finding = {
          'kind': 'finding',
          'code': 'TOKEN_ID_MISMATCH',
          'mirror': mirror,
          'prompt_id': id,
          'detail': 'rust candidate diverges from python_mlxlm reference at '
              'generated index $firstDivergence (py=${pyIds.length} ids, '
              'rust=${rustIds.length} ids; tolerance 0 on ids)',
        };
        findings.add(finding);
        out.add(finding);
      }
      if (!promptIdsEqual) {
        final finding = {
          'kind': 'finding',
          'code': 'PROMPT_ENCODING_DIVERGENCE',
          'mirror': mirror,
          'prompt_id': id,
          'detail': 'prompt token ids differ across engines '
              '(py=${(pEv['prompt_token_ids'] as List).length} ids, '
              'rust=${(rEv['prompt_token_ids'] as List).length} ids) — '
              'tokenizer surface, attributed separately from decode',
        };
        findings.add(finding);
        out.add(finding);
      }
      final group = groupOf[id]!;
      final pyContent = pEv['content_tokens'] as int;
      final rustContent = rEv['content_tokens'] as int;
      pyCounts[group]!.add(pyContent);
      rustCounts[group]!.add(rustContent);
      out.add({
        'kind': 'cell',
        'mirror': mirror,
        'prompt_id': id,
        'group': group,
        'cap': capOf[id],
        'ids_equal': idsEqual,
        'prompt_ids_equal': promptIdsEqual,
        'tokens_py': pyIds.length,
        'tokens_rust': rustIds.length,
        'content_tokens_py': pyContent,
        'content_tokens_rust': rustContent,
        'cap_hit_py': pEv['cap_hit'],
        'cap_hit_rust': rEv['cap_hit'],
        'ids_sha256_py': shaOf(pyIds),
        'ids_sha256_rust': shaOf(rustIds),
        if (!idsEqual) 'first_divergence_index': firstDivergence,
      });

      // bundle cells: per-cell cap-hit indicator under the frozen rule
      final pyHit = (pEv['cap_hit'] as bool) ? 1.0 : 0.0;
      final rustHit = (rEv['cap_hit'] as bool) ? 1.0 : 0.0;
      pyCells.add(CellDigest(
        cell: id,
        logitsDigest: shaOf(pyIds),
        behaviorDigest: shaOf({'content': pyContent, 'hit': pEv['cap_hit']}),
        behaviorValue: pyHit,
      ));
      rustCells.add(CellDigest(
        cell: id,
        logitsDigest: shaOf(rustIds),
        behaviorDigest: shaOf({'content': rustContent, 'hit': rEv['cap_hit']}),
        behaviorValue: rustHit,
      ));
    }

    // frozen per-mirror loop rates (scorers.dart tokenLimitRate)
    final rates = <String, Map<String, double>>{};
    for (final spec in [('python_mlxlm', pyCounts, pyCells),
      ('rust', rustCounts, rustCells)]) {
      final name = spec.$1;
      final counts = spec.$2;
      final cellList = spec.$3;
      final rateG2 = tokenLimitRate(counts['G2']!, g2Cap);
      final rateG0 = tokenLimitRate(counts['G0']!, g0Cap);
      rates[name] = {'G2': rateG2, 'G0': rateG0};
      for (final g in ['G2', 'G0']) {
        final rate = g == 'G2' ? rateG2 : rateG0;
        final groupIds = ids.where((i) => groupOf[i] == g).toList();
        final concat = groupIds
            .map((i) => cellList.firstWhere((c) => c.cell == i).logitsDigest)
            .join();
        cellList.add(CellDigest(
          cell: 'loop_rate_$g',
          logitsDigest: shaOf(concat),
          behaviorDigest: shaOf({'mirror': mirror, 'group': g, 'rate': rate}),
          behaviorValue: rate,
        ));
      }
    }

    final verdict = CrossEngineCertification.certify(
      a: DigestBundle(engine: CrossEngine.pythonMlxlm, cells: pyCells),
      b: DigestBundle(engine: CrossEngine.rust, cells: rustCells),
      tolerance: Tolerance(abs: 0, rel: 0),
    );
    final row = {
      'kind': 'certify',
      'mirror': mirror,
      'tolerance': {'abs': 0.0, 'rel': 0.0},
      'loop_rate_py': rates['python_mlxlm'],
      'loop_rate_rust': rates['rust'],
      'verdict': verdict.toJson(),
    };
    certifyRows.add(row);
    out.add(row);
  }

  final allAgree = certifyRows.every(
      (r) => (r['verdict'] as Map)['verdict'] == 'AGREE');
  final overall =
      (allAgree && idsMismatchTotal == 0 && findings.isEmpty) ? 'PASS' : 'FAIL';
  out.add({
    'kind': 'summary',
    'tool': 'ws2_certify_dart.dart',
    'created_utc': DateTime.now().toUtc().toIso8601String(),
    'mirrors': mirrors,
    'cells_per_mirror': ids.length,
    'cell_pairs_compared': idsEqualTotal + idsMismatchTotal,
    'token_id_pairs_equal': idsEqualTotal,
    'token_id_pairs_mismatched': idsMismatchTotal,
    'findings': findings,
    'certify_verdicts': {
      for (final r in certifyRows)
        r['mirror'] as String: (r['verdict'] as Map)['verdict'],
    },
    'loop_rates': {
      for (final r in certifyRows)
        r['mirror'] as String: {
          'python_mlxlm': r['loop_rate_py'],
          'rust': r['loop_rate_rust'],
        },
    },
    'non_claims': [
      'LOGITS_DIGEST_NOT_CAPTURED: raw-logits digests are optional identity '
          'evidence; token-id sequence digests key these bundles instead',
      'wall_ms/tok_s rows are non-claims under contention (house law)',
    ],
    'overall_verdict': overall,
  });

  File(outPath)
      .writeAsStringSync('${out.map((r) => jsonEncode(r)).join('\n')}\n');
  stdout.writeln('WS2_CERTIFY_DONE overall=$overall '
      'ids_equal=$idsEqualTotal ids_mismatch=$idsMismatchTotal '
      'certify=${out.last['certify_verdicts']} -> $outPath');
  // Exit 0 = the certification RAN and the truth is written; PASS/FAIL is
  // data in the summary row (a mismatch is a measured finding, journaled —
  // not a tool failure). Operational refusals exit 1 via refuse().
  exit(0);
}
