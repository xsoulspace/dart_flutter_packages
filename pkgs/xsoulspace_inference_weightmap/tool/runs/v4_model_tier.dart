// v4_model_tier.dart — V-4 MODEL TIER runner (PREREG-C §V-4 model tier +
// addendum 2026-11-05 "case blind spot").
//
// CPU-only rescore of the DIGEST-VERIFIED archived A3 per-arm battery outputs
// for the six certified edits (plants 1,3,4,5,6,7): does the certification
// evidence survive the frozen format-invariance wrapper (frozen four
// perturbations, scorers.dart) plus the two bench-NAMED case variants
// (lowercase_all / uppercase_all, redteam.dart casePerturbations) restricted
// to text-label cells per the pre-registered applicability table?
//
// This is a MEASUREMENT, not a pass bar: FORMAT_ARTIFACT_SUSPECT findings are
// recorded and REOPEN the affected edit's certification; nothing here
// auto-revokes. No device generation; frozen oracles are read-only.
//
// The pre-run registration (applicability table, verdict rules,
// CASE_VARIANT_APPLICATION decision, reproduction-gate targets) is seq 0 of
// receipts/V4-model-tier.jsonl and MUST exist before this runner appends.
//
// Named halt codes (nothing is emitted on a halt except the v4-halt row):
//   FROZEN_CELLS_DIGEST_MISMATCH, PREREG_ROW_MISSING, CERTIFIED_SET_MISMATCH,
//   EVIDENCE_DIGEST_MISMATCH, EVIDENCE_MISSING, BATTERY_SHAPE_MISMATCH,
//   CAP_HIT_FIELD_MISMATCH, REPRODUCTION_MISMATCH.
//
// usage (from the package directory):
//   dart run tool/runs/v4_model_tier.dart [receiptsDir=receipts] [runsDir=tool/runs]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

// ---------------------------------------------------------------------------
// Frozen A3 scorer-spec implementation — copied VERBATIM from
// tool/runs/a3_score.dart (which implements the frozen 'scorers' text in
// cells_frozen_A3.json; frozen oracles themselves are never edited).
// ---------------------------------------------------------------------------

// FROZEN think_prefix_strip: if the output (lstrip) starts with the opening
// think tag, drop everything through the first closing think tag inclusive.
// Implemented via split() so no tag literal appears in this source.
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

// ---------------------------------------------------------------------------
// Receipt-row plumbing (same {"digest","kind","payload"} convention as
// receipts/V1-nulls.jsonl; digest = sha256 of the exact payload json text).
// ---------------------------------------------------------------------------

String sha256File(String p) =>
    sha256.convert(File(p).readAsBytesSync()).toString();

String encodeRow(String kind, Map<String, Object?> payload) {
  final s = jsonEncode(payload);
  final d = sha256.convert(utf8.encode(s)).toString();
  return '{"digest":"$d","kind":"$kind","payload":$s}';
}

List<Map<String, Object?>> readJsonl(File f) => f
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => (jsonDecode(l) as Map).cast<String, Object?>())
    .toList();

Never halt(File jsonl, String reason) {
  final row = encodeRow('v4-halt', {
    'artifact': 'V-4 model tier HALT',
    'at': DateTime.now().toUtc().toIso8601String(),
    'reason': reason,
  });
  jsonl.writeAsStringSync('$row\n', mode: FileMode.append);
  stderr.writeln('V4_HALT: $reason');
  exit(2);
}

// ---------------------------------------------------------------------------
// Per-cell measurement
// ---------------------------------------------------------------------------

class CellMeasurement {
  CellMeasurement({
    required this.cellId,
    required this.group,
    required this.scorer,
    required this.caseApplicable,
    required this.stages,
  });

  final String cellId;
  final String group;
  final String scorer;
  final bool caseApplicable;

  /// stage ('M'/'R') -> measurement map.
  final Map<String, Map<String, Object?>> stages;

  bool get suspect => stages.values
      .any((s) => (s['naive']! as double) > (s['invariant_all']! as double));

  List<Map<String, Object?>> suspectDetail() => [
        for (final e in stages.entries)
          if ((e.value['naive']! as double) >
              (e.value['invariant_all']! as double))
            {
              'stage': e.key,
              'naive': e.value['naive'],
              'invariant_all': e.value['invariant_all'],
              'killer': e.value['killer'],
            },
      ];
}

void main(List<String> args) {
  final receiptsDir = args.isNotEmpty ? args[0] : 'receipts';
  final runsDir = args.length > 1 ? args[1] : 'tool/runs';
  final cellsPath = '$runsDir/cells_frozen_A3.json';
  final joinPath = '$receiptsDir/A3/join-table.json';
  final evidenceDir = '$receiptsDir/V4-model-tier-evidence';
  final outJsonl = File('$receiptsDir/V4-model-tier.jsonl');
  final summaryPath = '$receiptsDir/V4-model-tier-summary.md';

  // Gate: frozen cells digest (A4 key recorded in VERDICTS.md + prereg row).
  const frozenCellsSha =
      '8406130623b6e85922eac6cbd92b73dd2282e6fc19538bb3c199f647f518d760';
  if (!File(cellsPath).existsSync()) {
    stderr.writeln('V4_HALT: EVIDENCE_MISSING: $cellsPath');
    exit(2);
  }
  final cellsSha = sha256File(cellsPath);
  if (cellsSha != frozenCellsSha) {
    stderr.writeln(
      'V4_HALT: FROZEN_CELLS_DIGEST_MISMATCH: $cellsPath sha $cellsSha != '
      'A4 key $frozenCellsSha',
    );
    exit(2);
  }
  if (!outJsonl.existsSync()) {
    stderr.writeln(
      'V4_HALT: PREREG_ROW_MISSING: ${outJsonl.path} — the pre-run '
      'registration row must exist before any measurement row',
    );
    exit(2);
  }
  final preregLine = outJsonl.readAsLinesSync().first;
  final preregDigest =
      (jsonDecode(preregLine) as Map)['digest'] as String;

  final cells =
      jsonDecode(File(cellsPath).readAsStringSync()) as Map<String, Object?>;
  final groups = (cells['cells']! as Map).cast<String, Object?>();
  final caps =
      ((cells['surface']! as Map)['caps']! as Map).cast<String, Object?>();
  final allCells = <Map<String, Object?>>[
    for (final g in ['G0', 'G1', 'G2'])
      ...(groups[g]! as List).cast<Map<String, Object?>>(),
  ];
  final byId = {for (final c in allCells) c['id']! as String: c};

  // Gate: certified set from the archived join table = plants 1,3,4,5,6,7.
  final join =
      jsonDecode(File(joinPath).readAsStringSync()) as Map<String, Object?>;
  final joinRows = (join['rows']! as List).cast<Map<String, Object?>>();
  const expectedSet = {
    'a3-plant-1': 'arm-002',
    'a3-plant-3': 'arm-009',
    'a3-plant-4': 'arm-005',
    'a3-plant-5': 'arm-015',
    'a3-plant-6': 'arm-011',
    'a3-plant-7': 'arm-012',
  };
  final certified = {
    for (final r in joinRows)
      if (r['kind'] == 'plant' && r['certified'] == true)
        r['real_id']! as String: r,
  };
  final observedSet = {
    for (final e in certified.entries) e.key: e.value['label']! as String,
  };
  if (jsonEncode(observedSet) != jsonEncode(expectedSet)) {
    stderr.writeln(
      'V4_HALT: CERTIFIED_SET_MISMATCH: observed $observedSet != expected '
      '$expectedSet (source: $joinPath)',
    );
    exit(2);
  }

  final cellRows = <String>[];
  final editRows = <String>[];
  final editSummaries = <Map<String, Object?>>[];

  for (final editId in expectedSet.keys.toList()..sort()) {
    final joinRow = certified[editId]!;
    final label = joinRow['label']! as String;
    final mFile = File('$evidenceDir/$label/battery_M.jsonl');
    final rFile = File('$evidenceDir/$label/battery_R.jsonl');
    if (!mFile.existsSync() || !rFile.existsSync()) {
      halt(
        outJsonl,
        'EVIDENCE_MISSING: ${mFile.path} / ${rFile.path} (originals: '
        '\$TMPDIR/wm-a3/blind/$label/; copies are the scored inputs)',
      );
    }
    // Gate: evidence digests == archived join-table digests (which equal the
    // archived tmpdir-artifact-manifest digests; triple-checked pre-run).
    final mSha = sha256File(mFile.path);
    final rSha = sha256File(rFile.path);
    final wantM = (joinRow['digests']! as Map)['battery_M']! as String;
    final wantR = (joinRow['digests']! as Map)['battery_R']! as String;
    if (mSha != wantM || rSha != wantR) {
      halt(
        outJsonl,
        'EVIDENCE_DIGEST_MISMATCH: $label battery_M $mSha != $wantM / '
        'battery_R $rSha != $wantR',
      );
    }

    final rowsM = readJsonl(mFile);
    final rowsR = readJsonl(rFile);
    final expectedOrder = [for (final c in allCells) c['id']! as String];
    for (final pair in [['M', rowsM], ['R', rowsR]]) {
      final stage = pair[0] as String;
      final rows = (pair[1] as List).cast<Map<String, Object?>>();
      var orderOk = rows.length == expectedOrder.length;
      for (var i = 0; orderOk && i < rows.length; i++) {
        if (rows[i]['cell_id'] != expectedOrder[i]) orderOk = false;
      }
      if (!orderOk) {
        halt(
          outJsonl,
          'BATTERY_SHAPE_MISMATCH: $label stage $stage rows=${rows.length} '
          'or cell order deviates from cells_frozen_A3.json',
        );
      }
    }

    // ---- naive rescore (frozen certifier semantics) ----
    Map<String, bool> passOf(List<Map<String, Object?>> rows) => {
          for (final r in rows)
            if (r['group'] != 'G2')
              r['cell_id']! as String:
                  scoreCell(byId[r['cell_id']! as String]!, r['output']! as String),
        };
    List<int> g2Counts(List<Map<String, Object?>> rows) => [
          for (final r in rows)
            if (r['group'] == 'G2') r['generated_tokens']! as int,
        ];
    // cap_hit field sanity (frozen instrument contract).
    for (final r in [...rowsM, ...rowsR]) {
      final cap = caps[r['group']! as String]! as int;
      if ((r['generated_tokens']! as int) >= cap != (r['cap_hit']! as bool) ||
          r['cap'] != cap) {
        halt(
          outJsonl,
          'CAP_HIT_FIELD_MISMATCH: $label ${r['cell_id']} generated_tokens='
          '${r['generated_tokens']} cap=${r['cap']}/$cap cap_hit=${r['cap_hit']}',
        );
      }
    }

    final passM = passOf(rowsM);
    final passR = passOf(rowsR);
    final loopM = tokenLimitRate(g2Counts(rowsM), caps['G2']! as int);
    final loopR = tokenLimitRate(g2Counts(rowsR), caps['G2']! as int);
    final taskPassM = passM.values.where((p) => p).length;
    final taskPassR = passR.values.where((p) => p).length;
    final flips = <Map<String, Object?>>[
      for (final id in expectedOrder)
        if (passM.containsKey(id) && passM[id] != passR[id])
          {'cell_id': id, 'M': passM[id], 'R': passR[id]},
    ];

    // ---- reproduction gate (pre-registered targets, exact) ----
    String reproFail(String field, Object? got, Object? want) =>
        'REPRODUCTION_MISMATCH: $editId($label) $field recomputed=$got '
        'archived=$want';
    if (loopM != (joinRow['loop_rate_M']! as double)) {
      halt(outJsonl, reproFail('loop_rate_M', loopM, joinRow['loop_rate_M']));
    }
    if (loopR != (joinRow['loop_rate_R']! as double)) {
      halt(outJsonl, reproFail('loop_rate_R', loopR, joinRow['loop_rate_R']));
    }
    if (taskPassM / 22 != (joinRow['task_success_M']! as double)) {
      halt(
        outJsonl,
        reproFail('task_success_M', taskPassM / 22, joinRow['task_success_M']),
      );
    }
    if (taskPassR / 22 != (joinRow['task_success_R']! as double)) {
      halt(
        outJsonl,
        reproFail('task_success_R', taskPassR / 22, joinRow['task_success_R']),
      );
    }
    final archivedFlips =
        (joinRow['flips']! as List).cast<Map<String, Object?>>();
    if (archivedFlips.length != flips.length ||
        !archivedFlips.every((f) => flips.any((g) =>
            g['cell_id'] == f['cell_id'] && g['M'] == f['M'] && g['R'] == f['R']))) {
      halt(
        outJsonl,
        reproFail('flips', jsonEncode(flips), jsonEncode(archivedFlips)),
      );
    }

    // ---- invariant measurement (per pre-run applicability) ----
    final outM = {for (final r in rowsM) r['cell_id']! as String: r};
    final outR = {for (final r in rowsR) r['cell_id']! as String: r};
    final measurements = <CellMeasurement>[];
    var invAllPassM = 0.0, invAllPassR = 0.0; // task cells, full invariant
    var inv4PassM = 0.0, inv4PassR = 0.0; // task cells, frozen four only
    var rawMinPassM = 0.0, rawMinPassR = 0.0; // task cells, raw-case min (secondary)
    var rawUpperKilledM = 0, rawUpperKilledR = 0; // observation over ALL 22 task cells
    var rawUpperScoredM = 0, rawUpperScoredR = 0;

    for (final cell in allCells) {
      final id = cell['id']! as String;
      final group = cell['group']! as String;
      final scorer = cell['scorer']! as String;
      final isLoop = group == 'G2';
      final caseApplies = !isLoop && scorer == 'label_first_line';
      final cap = caps[group]! as int;
      final stages = <String, Map<String, Object?>>{};

      for (final stage in ['M', 'R']) {
        final raw = ((stage == 'M' ? outM : outR)[id]!['output']! as String);
        if (isLoop) {
          final looped =
              ((stage == 'M' ? outM : outR)[id]!['generated_tokens']! as int) >=
                      cap
                  ? 1.0
                  : 0.0;
          stages[stage] = {
            'naive': looped,
            'invariant4': looped,
            'case_typed': null,
            'case_raw_secondary': null,
            'invariant_all': looped,
            'killer': null,
            'note': 'IDENTITY_BY_CONSTRUCTION: token_limit_cap consumes the '
                'exact recorded generated-token count, not the output text',
          };
          continue;
        }
        double cellScore(String o) => scoreCell(cell, o) ? 1.0 : 0.0;
        final naive = cellScore(raw);
        final inv4 = formatInvariantScore(cellScore, raw);

        Map<String, double>? typedScores;
        Map<String, double>? rawScores;
        double? caseMinTyped;
        double? caseMinRaw;
        if (caseApplies) {
          // PRIMARY (verdict-driving): case variants on the answer surface
          // (after the frozen spec's think_prefix_strip), per pre-run
          // CASE_VARIANT_APPLICATION decision.
          final stripped = thinkStrip(raw);
          typedScores = {
            for (final p in casePerturbations(stripped))
              p.name: cellScore(p.output),
          };
          // SECONDARY (recorded, not verdict-driving): variants on the raw
          // output (redteam.dart byte-site application).
          rawScores = {
            for (final p in casePerturbations(raw))
              p.name: cellScore(p.output),
          };
          caseMinTyped =
              typedScores.values.reduce(math.min);
          caseMinRaw = rawScores.values.reduce(math.min);
        }

        final invariantAll =
            caseMinTyped == null ? inv4 : math.min(inv4, caseMinTyped);

        // Killer: first perturbation (frozen four in frozen order, then the
        // cell-typed case variants) scoring below naive.
        String? killer;
        for (final p in surfacePerturbations(raw)) {
          if (cellScore(p.output) < naive) {
            killer = p.name;
            break;
          }
        }
        if (killer == null && typedScores != null) {
          for (final e in typedScores.entries) {
            if (e.value < naive) {
              killer = '${e.key}:cell_typed';
              break;
            }
          }
        }

        stages[stage] = {
          'naive': naive,
          'invariant4': inv4,
          'case_typed': typedScores == null
              ? null
              : {
                  'lowercase_all': typedScores['lowercase_all'],
                  'uppercase_all': typedScores['uppercase_all'],
                  'min': caseMinTyped,
                },
          'case_raw_secondary': rawScores == null
              ? null
              : {
                  'lowercase_all': rawScores['lowercase_all'],
                  'uppercase_all': rawScores['uppercase_all'],
                  'min': caseMinRaw,
                },
          'invariant_all': invariantAll,
          'killer': killer,
        };

        if (stage == 'M') {
          inv4PassM += inv4;
          invAllPassM += invariantAll;
          rawMinPassM +=
              caseMinRaw == null ? inv4 : math.min(inv4, caseMinRaw);
          rawUpperScoredM++;
          if (cellScore(raw.toUpperCase()) < naive) rawUpperKilledM++;
        } else {
          inv4PassR += inv4;
          invAllPassR += invariantAll;
          rawMinPassR +=
              caseMinRaw == null ? inv4 : math.min(inv4, caseMinRaw);
          rawUpperScoredR++;
          if (cellScore(raw.toUpperCase()) < naive) rawUpperKilledR++;
        }
      }

      final m = CellMeasurement(
        cellId: id,
        group: group,
        scorer: scorer,
        caseApplicable: caseApplies,
        stages: stages,
      );
      measurements.add(m);
      cellRows.add(encodeRow('v4-cell', {
        'edit': editId,
        'label': label,
        'cell_id': id,
        'group': group,
        'scorer': scorer,
        'applicability': {
          'frozen_four': isLoop ? 'IDENTITY_BY_CONSTRUCTION' : 'APPLIES',
          'case_variants': caseApplies
              ? 'APPLIES (cell-typed primary; raw secondary)'
              : (isLoop
                  ? 'NOT_APPLICABLE (non-text token-count scorer)'
                  : (scorer == 'numeric_final'
                      ? 'NOT_APPLICABLE (numeric cell keeps the frozen four)'
                      : 'NOT_APPLICABLE (gold case-spec’d by its own checker spec)')),
        },
        'M': stages['M'],
        'R': stages['R'],
        'suspect': m.suspect,
        if (m.suspect) 'suspect_detail': m.suspectDetail(),
      }));
    }

    // ---- aggregate re-certification ----
    final certifiedNaive = loopR < loopM && taskPassR >= taskPassM;
    final certifiedFrozen4 = loopR < loopM && inv4PassR >= inv4PassM;
    final certifiedFull = loopR < loopM && invAllPassR >= invAllPassM;
    final certifiedRawMin = loopR < loopM && rawMinPassR >= rawMinPassM;

    final suspects =
        measurements.where((m) => m.suspect).toList(growable: false);
    final killers = <String>{
      for (final s in suspects)
        for (final d in s.suspectDetail()) d['killer']! as String,
    };
    final verdict = suspects.isEmpty
        ? 'SURVIVES'
        : (killers.every((k) => k.endsWith(':cell_typed'))
            ? 'FORMAT_ARTIFACT_SUSPECT:case'
            : 'FORMAT_ARTIFACT_SUSPECT');

    editRows.add(encodeRow('v4-edit', {
      'artifact': 'V-4 model-tier per-edit verdict',
      'at': DateTime.now().toUtc().toIso8601String(),
      'edit': editId,
      'label': label,
      'evidence_sha256': {'battery_M': mSha, 'battery_R': rSha},
      'reproduction_gate': {
        'status': 'MATCH',
        'loop_rate_M': loopM,
        'loop_rate_R': loopR,
        'task_pass_M': taskPassM,
        'task_pass_R': taskPassR,
        'task_total': 22,
        'flips': flips,
      },
      'aggregate': {
        'certified_naive_recomputed': certifiedNaive,
        'certified_frozen4': certifiedFrozen4,
        'certified_invariant_full': certifiedFull,
        'certified_raw_case_min_secondary': certifiedRawMin,
        'task_pass_frozen4_M': inv4PassM,
        'task_pass_frozen4_R': inv4PassR,
        'task_pass_invariant_all_M': invAllPassM,
        'task_pass_invariant_all_R': invAllPassR,
        'task_pass_raw_case_min_M_secondary': rawMinPassM,
        'task_pass_raw_case_min_R_secondary': rawMinPassR,
        'loop_rate_invariant': 'unchanged (token counts are perturbation-invariant)',
      },
      'raw_uppercase_observation_secondary': {
        'note': 'RAW_UPPERCASE_UNIFORM_KILL observation: raw uppercase_all '
            'defeats the case-sensitive frozen think_prefix_strip and kills '
            'first-line cells in BOTH stages uniformly; recorded, not '
            'verdict-driving (pre-run CASE_VARIANT_APPLICATION)',
        'killed_naive_passes_M': rawUpperKilledM,
        'killed_naive_passes_R': rawUpperKilledR,
        'task_cells_scored_M': rawUpperScoredM,
        'task_cells_scored_R': rawUpperScoredR,
      },
      'suspect_cells': [
        for (final s in suspects)
          {'cell_id': s.cellId, 'detail': s.suspectDetail()},
      ],
      'suspect_count': suspects.length,
      'killers': killers.toList()..sort(),
      'verdict': verdict,
    }));

    editSummaries.add({
      'edit': editId,
      'label': label,
      'loop': '$loopM -> $loopR',
      'task_naive': '$taskPassM -> $taskPassR',
      'task_inv4': '${inv4PassM.toInt()} -> ${inv4PassR.toInt()}',
      'task_inv_all': '${invAllPassM.toInt()} -> ${invAllPassR.toInt()}',
      'task_rawmin': '${rawMinPassM.toInt()} -> ${rawMinPassR.toInt()}',
      'certified_full': certifiedFull,
      'suspects': suspects.length,
      'verdict': verdict,
      'rawUpperKilled': '$rawUpperKilledM/$rawUpperKilledR',
    });
  }

  final survivors =
      editSummaries.where((e) => e['verdict'] == 'SURVIVES').length;
  final suspectEdits = editSummaries.length - survivors;

  final summaryPayload = {
    'artifact': 'V-4 MODEL TIER summary (PREREG-C §V-4 model tier + addendum)',
    'at': DateTime.now().toUtc().toIso8601String(),
    'tier': 'model (CPU-only rescore; NO device generation; fallback NOT run)',
    'prereg_row_digest': preregDigest,
    'denominator': '6 of 6 A3-certified edits (plants 1,3,4,5,6,7)',
    'survivors': survivors,
    'suspects': suspectEdits,
    'verdict_rule': 'per-cell suspect := naive > invariant_all (frozen four ∪ '
        'cell-typed case variants on applicable text-label cells); edit '
        'verdict FORMAT_ARTIFACT_SUSPECT(:case) iff any certification cell '
        'suspect; MEASUREMENT, not a pass bar — suspects reopen certification, '
        'no auto-revoke',
    'reproduction_gate': 'MATCH on all 6 edits (loop rates, task passes, flips '
        'identical to archived join-table)',
    'evidence_source':
        'digest-verified copies under receipts/V4-model-tier-evidence/ of '
            '\$TMPDIR/wm-a3/blind/<label>/battery_{M,R}.jsonl (originals '
            'triple-verified == receipts/A3/tmpdir-artifact-manifest.json == '
            'join-table digests)',
    'fallback_ran': false,
    'named_issues': [
      'EVIDENCE_SOURCE_TMPDIR_DIGEST_VERIFIED (originals sweepable; copies durable)',
      'CASE_VARIANT_APPLICATION_NOTE (cell-typed primary after frozen think_prefix_strip; raw application recorded secondary)',
      'RAW_UPPERCASE_UNIFORM_KILL (secondary observation; non-discriminating across M/R)',
      'FALLBACK_NOT_RUN (per-arm raw outputs archived and digest-verified; no device run)',
      'V1_HALT_CONTEXT (measurement of archived evidence under the recorded NULL_LEAK halt; no revocation authority)',
    ],
    'edits': editSummaries,
    'runner': {
      'script': 'tool/runs/v4_model_tier.dart',
      'script_sha256': sha256File(Platform.script.toFilePath()),
      'cells_frozen_sha256': cellsSha,
    },
  };

  final buf = StringBuffer();
  for (final r in [...cellRows, ...editRows]) {
    buf.writeln(r);
  }
  buf.writeln(encodeRow('v4-summary', summaryPayload));
  outJsonl.writeAsStringSync(buf.toString(), mode: FileMode.append);

  // ---- summary markdown ----
  final md = StringBuffer();
  md.writeln('# V-4 MODEL TIER — certification evidence under invariance + case variants');
  md.writeln('');
  md.writeln('PREREG-C §V-4 model tier + addendum 2026-11-05. MEASUREMENT, not a pass bar:');
  md.writeln('suspects are findings that REOPEN an edit’s certification (recorded, never auto-revoked).');
  md.writeln('CPU-only rescore of digest-verified archived A3 outputs — NO device generation, fallback NOT run.');
  md.writeln('');
  md.writeln('- Pre-run registration: `receipts/V4-model-tier.jsonl` seq 0, digest `$preregDigest`');
  md.writeln('- Certified set (join-table): plants 1,3,4,5,6,7 = arm-002/009/005/015/011/012');
  md.writeln('- Evidence: `receipts/V4-model-tier-evidence/<label>/battery_{M,R}.jsonl` — copies of');
  md.writeln('  `\$TMPDIR/wm-a3/blind/<label>/…`, triple-verified (file == manifest == join-table digest)');
  md.writeln('- Frozen inputs verified pre-run: scorers.dart `dfe42d43…`, probes.dart `7236f69e…`,');
  md.writeln('  cells_frozen_A3.json `84061306…`, sampler_config_frozen.json `cbf0132d…` (A4 keys, match)');
  md.writeln('- Reproduction gate: naive recomputation == archived join-table aggregates on all 6 edits');
  md.writeln('  (loop_rate_M/R, task_pass_M/R, full flips lists) — MATCH');
  md.writeln('');
  md.writeln('## Applicability table (PRE-RUN, from seq 0)');
  md.writeln('');
  md.writeln('| cells | scorer | frozen four | case variants | reason |');
  md.writeln('|---|---|---|---|---|');
  md.writeln('| g0-c2s, g0-ws, g0-rle, g0-kebab-2, g0-s2c, g0-title, g0-acr | string_first_line | APPLIES | NOT_APPLICABLE | golds case-spec’d by their own checker spec (case-SENSITIVE equality); case is task content, not format |');
  md.writeln('| g0-pal | label_first_line | APPLIES | APPLIES | closed boolean label, case-insensitive gold |');
  md.writeln('| g0-vowels, g0-clamp | numeric_final | APPLIES | NOT_APPLICABLE | numeric cells keep the frozen four (addendum) |');
  md.writeln('| g1-perm-01..12 | label_first_line | APPLIES | APPLIES | closed-set labels (allow_once/abstain), case-insensitive golds |');
  md.writeln('| g2-* (12) | token_limit_cap | IDENTITY_BY_CONSTRUCTION | NOT_APPLICABLE | score consumes exact generated-token counts, not text |');
  md.writeln('');
  md.writeln('Case-variant application (pre-registered `CASE_VARIANT_APPLICATION`): PRIMARY =');
  md.writeln('variants applied to the answer surface after the frozen spec’s own think_prefix_strip');
  md.writeln('(same-answer-different-case semantics, matching the wrapper-free scorer-tier fixtures);');
  md.writeln('SECONDARY = variants on the raw output, recorded per cell. Raw uppercase_all rewrites');
  md.writeln('the structural <think> wrapper, defeating the case-sensitive frozen strip and');
  md.writeln('killing first-line cells in BOTH stages uniformly — non-discriminating, hence secondary.');
  md.writeln('');
  md.writeln('## Per-edit verdicts');
  md.writeln('');
  md.writeln('| edit | arm | loop M→R | task naive M→R | task inv4 M→R | task inv-all M→R | certified (invariant) | suspect cells | VERDICT |');
  md.writeln('|---|---|---|---|---|---|---|---|---|');
  for (final e in editSummaries) {
    md.writeln('| ${e['edit']} | ${e['label']} | ${e['loop']} | ${e['task_naive']} | '
        '${e['task_inv4']} | ${e['task_inv_all']} | ${e['certified_full']} | '
        '${e['suspects']} | **${e['verdict']}** |');
  }
  md.writeln('');
  md.writeln('Result: $survivors of ${editSummaries.length} certified edits SURVIVE the invariance');
  md.writeln('wrapper + applicable case variants; $suspectEdits FORMAT_ARTIFACT_SUSPECT.');
  md.writeln('');
  md.writeln('Secondary raw-case aggregates (task passes under the raw-application min, observation');
  md.writeln('only — NOT verdict-driving). Mechanism: raw uppercase_all defeats the case-sensitive');
  md.writeln('think_prefix_strip, so it kills EVERY naive pass on first-line-scored cells in BOTH');
  md.writeln('stages; numeric-cell passes can survive it (digits are case-invariant). Per-stage');
  md.writeln('kill counts below; the jsonl rows are authoritative.');
  for (final e in editSummaries) {
    md.writeln('- ${e['edit']} (${e['label']}): raw-min task ${e['task_rawmin']}; '
        'raw uppercase killed naive passes M/R = ${e['rawUpperKilled']}');
  }
  md.writeln('');
  md.writeln('## NAMED issues');
  md.writeln('');
  for (final n in summaryPayload['named_issues']! as List) {
    md.writeln('- $n');
  }
  md.writeln('');
  md.writeln('Rows: `receipts/V4-model-tier.jsonl` (seq 0 prereg + 204 v4-cell + 6 v4-edit + 1 v4-summary).');
  md.writeln('Runner: `tool/runs/v4_model_tier.dart` (new script; frozen oracles untouched).');
  File(summaryPath).writeAsStringSync(md.toString());

  stdout.writeln(
    'V-4 model tier: survivors=$survivors suspects=$suspectEdits of '
    '${editSummaries.length} certified edits; reproduction gate MATCH; '
    'fallback NOT run',
  );
  for (final e in editSummaries) {
    stdout.writeln(
      '${e['edit']} (${e['label']}): ${e['verdict']} '
      '(suspect_cells=${e['suspects']}, certified_invariant=${e['certified_full']})',
    );
  }
  stdout.writeln('receipt: ${outJsonl.path}');
  stdout.writeln('summary: $summaryPath');
}
