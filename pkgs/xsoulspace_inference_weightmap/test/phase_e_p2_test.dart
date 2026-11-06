// Phase E + P-2 machinery self-checks (PREREG-E / PREREG-D, FROZEN arms).
//
// Asserts the --dry-run PLAN of all five tool/runs scripts (ws4_train,
// v5_audit, v6_matrix, p2_runner, p2b_pool_builder) via Process.run with
// `python3 -I` — dry-runs need NO venv, NO network, NO model and write
// NOTHING. Hermetic real-run refusals are asserted too (NAMED errors, never
// silent): missing denominator/pool files, underpowered audit, unfrozen
// budgets, corrupt pool digests. The ws4 arm list is asserted to match
// PREREG-E exactly (a-e) by parsing the --dry-run plan.
//
// The ws4 REAL-run test (arm training on a synthetic denominator) runs only
// when the wm-mlx venv with numpy exists; otherwise it SKIPS with the NAMED
// reason WM_VENV_ABSENT (repo law: skips are named, never silent).
//
// Frozen-file guard: every test asserts VERDICTS.md is byte-identical before
// and after — the machinery records evidence, it never writes the ledger.
@Timeout(Duration(seconds: 240))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// Walks up from [start] looking for the package marker file.
Directory? _findPackageRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File('${dir.path}/tool/runs/ws4_train.py').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Directory? _packageRoot() =>
    _findPackageRoot(Directory.current) ??
    _findPackageRoot(Directory(Platform.script.toFilePath()).parent);

bool _pythonAvailable() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The wm-mlx venv python (same default the scripts use), or null.
String? _venvPython() {
  final candidates = [
    Platform.environment['WM4_VENV_PYTHON'],
    '${Platform.environment['HOME']}/.local/share/wm-mlx/bin/python',
  ];
  for (final c in candidates) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
  }
  return null;
}

bool _venvHasNumpy(String py) {
  try {
    return Process.runSync(py, ['-c', 'import numpy']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Synthetic fixtures (deterministic; no rng)
// ---------------------------------------------------------------------------

/// ws4-denominator/v1 rows: [families] x [rowsPerFamily] candidate edits.
/// battery_pass correlates with delta_norm so the arms have signal to find
/// (the tests assert MACHINERY, never a result).
List<String> _denominatorLines({
  required int families,
  required int rowsPerFamily,
}) {
  final lines = <String>[];
  var n = 0;
  for (var f = 0; f < families; f++) {
    for (var k = 0; k < rowsPerFamily; k++) {
      n++;
      final deltaNorm = 0.5 + ((n * 37) % 100) / 28.0;
      final l1 = (n * 3) % 24;
      final l2 = (l1 + 4) % 24;
      final layers = [l1, l2]..sort();
      final columnCount = 2 + (n % 3);
      final cols = <int>{
        for (var j = 0; j < columnCount; j++) (n * 97 + j * 131) % 3584,
      }.toList()
        ..sort();
      // Dedupe by VALUE (a Set<List> would dedupe by identity): encode the
      // (layer, band) pair into one int key, then decode + sort.
      final bandKeys = <int>{
        for (final l in layers)
          for (final c in cols) l * 100000 + (c ~/ 256),
      }.toList()
        ..sort();
      final bands = [
        for (final key in bandKeys) [key ~/ 100000, key % 100000],
      ];
      lines.add(jsonEncode({
        'attempt_id': 'att-${n.toString().padLeft(3, '0')}',
        'arm': const ['A3', 'V-1', 'V-3'][f % 3],
        'family': 'fam-${f.toString().padLeft(2, '0')}',
        'features': {
          'delta_norm': double.parse(deltaNorm.toStringAsFixed(4)),
          'column_count': cols.length,
          'layer_ids': layers,
          'baseline_loop_rate': 0.3 + ((n * 13) % 60) / 100.0,
          'capture_eigen_gap': ((n * 29) % 200) / 100.0 + 0.01,
          'layer_column_bands': bands,
        },
        'label': {'battery_pass': deltaNorm > 2.0},
      }));
    }
  }
  return lines;
}

/// v5-audit-sample/v1 rows. [calibrated]: scores track the label;
/// anti-correlated otherwise (drives SCREENER_UNCALIBRATED at a high
/// operating point).
List<String> _auditSampleLines({required int n, required bool calibrated}) {
  final lines = <String>[];
  for (var i = 0; i < n; i++) {
    final y = (i % 3) != 0;
    final pass = calibrated ? y : !y;
    lines.add(jsonEncode({
      'attempt_id': 's-${i.toString().padLeft(3, '0')}',
      'family': 'f-${(i % 8).toString().padLeft(2, '0')}',
      'ws4_score': (pass ? 0.8 : 0.2) + (i % 5) * 0.01,
      'ws3_prior_score': pass ? 0.7 : 0.3,
      'battery_pass': y,
    }));
  }
  return lines;
}

Map<String, Object?> _certKey({String quant = 'bf16'}) => {
  'baseDigest': 'a' * 64,
  'tokenizerDigest': 'b' * 64,
  'quant': quant,
  'samplerConfig': {'temp': 0},
  'engineRev': 'r1',
  'batteryDigest': 'c' * 64,
};

void _writeJsonl(File f, List<String> lines) =>
    f.writeAsStringSync('${lines.join('\n')}\n');

void main() {
  final root = _packageRoot();
  final skipReason = root == null
      ? 'PACKAGE_ROOT_NOT_FOUND: tool/runs/ws4_train.py not found from cwd '
          'or script dir'
      : (_pythonAvailable() ? null : 'PYTHON3_ABSENT: python3 not on PATH');
  final venvPy = _venvPython();
  final venvSkip = (venvPy != null && _venvHasNumpy(venvPy))
      ? null
      : 'WM_VENV_ABSENT: no wm-mlx venv python with numpy at '
          '${venvPy ?? '~/.local/share/wm-mlx/bin/python'} (dry-run tests do '
          'not need it; this real-run test does)';

  final ws4 = '${root?.path}/tool/runs/ws4_train.py';
  final v5 = '${root?.path}/tool/runs/v5_audit.py';
  final v6 = '${root?.path}/tool/runs/v6_matrix.py';
  final p2 = '${root?.path}/tool/runs/p2_runner.py';
  final p2b = '${root?.path}/tool/runs/p2b_pool_builder.py';
  final verdicts = '${root?.path}/VERDICTS.md';

  Future<ProcessResult> runPy(
    String script,
    List<String> args, {
    Map<String, String>? environment,
  }) =>
      Process.run('python3', ['-I', script, ...args],
          environment: environment);

  group('Phase E + P-2 machinery (dry-runnable, no live runs)', () {
    late Directory tmp;
    late String verdictsDigestBefore;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('phase_e_p2_');
      verdictsDigestBefore =
          sha256.convert(File(verdicts).readAsBytesSync()).toString();
    });

    tearDown(() {
      // Frozen-file guard: the machinery NEVER writes the ledger.
      final after =
          sha256.convert(File(verdicts).readAsBytesSync()).toString();
      expect(after, verdictsDigestBefore,
          reason: 'VERDICTS.md must be byte-identical (no ledger writes)');
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // WS-4
    // -------------------------------------------------------------------------

    test('ws4 --dry-run plan: arms a-e EXACTLY per PREREG-E, family split, '
        'frozen floors, propose-only banner, writes nothing', () async {
      final den = File('${tmp.path}/denominator.jsonl');
      _writeJsonl(den, _denominatorLines(families: 6, rowsPerFamily: 5));
      final outPath = '${tmp.path}/ws4_report.json';
      final res = await runPy(ws4,
          ['--denominator', den.path, '--out', outPath, '--dry-run']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['schema'], 'ws4-denominator/v1');
      // PREREG-E arms, exact letters and exact substance:
      expect(plan['arm_letters'], ['a', 'b', 'c', 'd', 'e']);
      final arms = (plan['arms'] as List).cast<Map<String, dynamic>>();
      expect(arms.map((a) => a['id']), [
        'a_logistic',
        'b_mlp_matched',
        'c_null',
        'd_exact_memo',
        'e_ngram_table',
      ]);
      expect(arms.map((a) => a['name']), [
        'logistic regression',
        'matched-parameter MLP',
        'null',
        'exact memo',
        'n-gram table',
      ]);
      expect(plan['metrics_per_arm'],
          ['auc', 'fnr_at_operating_point', 'evals_skipped_per_false_negative']);
      expect(plan['fnr_floor'], 0.10);
      expect(plan['seed'], 20261105);
      // split by FAMILY, never by row:
      final split = plan['split'] as Map<String, dynamic>;
      expect(split['train_rows'], 30 - split['holdout_rows']);
      final trainF = (split['train_families'] as List).cast<String>();
      final holdF = (split['holdout_families'] as List).cast<String>();
      expect(trainF.toSet().intersection(holdF.toSet()), isEmpty);
      expect(trainF.length + holdF.length, 6);
      expect(holdF.length, greaterThanOrEqualTo(1));
      // propose-only law is in the plan itself:
      expect(plan['propose_only'], isTrue);
      expect(plan['banner'].toString(), contains('NEVER certifies'));
      expect(plan['pass_bar_rule'].toString(), contains('retired'));
      expect(File(outPath).existsSync(), isFalse,
          reason: 'dry-run must not write the report');
    }, skip: skipReason);

    test('ws4 dry-run refuses a missing denominator, NAMED '
        'DENOMINATOR_MISSING', () async {
      final res = await runPy(ws4, [
        '--denominator', '${tmp.path}/absent.jsonl',
        '--out', '${tmp.path}/r.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('DENOMINATOR_MISSING'));
    }, skip: skipReason);

    test('ws4 dry-run refuses a schema-violating row, NAMED '
        'DENOMINATOR_SCHEMA_ERROR', () async {
      final lines = _denominatorLines(families: 2, rowsPerFamily: 2);
      final bad = jsonDecode(lines.first) as Map<String, dynamic>;
      (bad['features'] as Map).remove('baseline_loop_rate');
      lines[1] = jsonEncode(bad);
      final den = File('${tmp.path}/bad.jsonl')..writeAsStringSync(
          '${lines.join('\n')}\n');
      final res = await runPy(ws4,
          ['--denominator', den.path, '--out', '${tmp.path}/r.json',
           '--dry-run']);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('DENOMINATOR_SCHEMA_ERROR'));
      expect(res.stderr.toString(), contains('baseline_loop_rate'));
    }, skip: skipReason);

    test('ws4 dry-run ACCEPTS capture_eigen_gap absence (PREREG-E Addendum '
        '2026-11-06 feature-set v2: optional-absent, never imputed) and '
        'refuses a malformed present value', () async {
      // v2 rows: eigen-gap absent on every row -> schema-legal.
      final lines = _denominatorLines(families: 2, rowsPerFamily: 2)
          .map((l) {
        final row = jsonDecode(l) as Map<String, dynamic>;
        (row['features'] as Map).remove('capture_eigen_gap');
        return jsonEncode(row);
      }).toList();
      final den = File('${tmp.path}/v2.jsonl')..writeAsStringSync(
          '${lines.join('\n')}\n');
      final res = await runPy(ws4,
          ['--denominator', den.path, '--out', '${tmp.path}/r.json',
           '--dry-run']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect((plan['denominator'] as Map)['rows'], 4);
      // present-but-malformed eigen-gap still refuses, NAMED:
      final bad = jsonDecode(lines.first) as Map<String, dynamic>;
      (bad['features'] as Map)['capture_eigen_gap'] = 'not-a-number';
      final badLines = [jsonEncode(bad), ...lines.sublist(1)];
      final badDen = File('${tmp.path}/v2bad.jsonl')..writeAsStringSync(
          '${badLines.join('\n')}\n');
      final res2 = await runPy(ws4,
          ['--denominator', badDen.path, '--out', '${tmp.path}/r.json',
           '--dry-run']);
      expect(res2.exitCode, 1);
      expect(res2.stderr.toString(), contains('DENOMINATOR_SCHEMA_ERROR'));
      expect(res2.stderr.toString(), contains('capture_eigen_gap'));
    }, skip: skipReason);

    test('ws4 dry-run refuses a single-family denominator, NAMED '
        'SPLIT_DEGENERATE (rows never split)', () async {
      final den = File('${tmp.path}/one_fam.jsonl');
      _writeJsonl(den, _denominatorLines(families: 1, rowsPerFamily: 4));
      final res = await runPy(ws4,
          ['--denominator', den.path, '--out', '${tmp.path}/r.json',
           '--dry-run']);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('SPLIT_DEGENERATE'));
    }, skip: skipReason);

    test('ws4 real run without the venv refuses after a zero poll, NAMED '
        'VENV_MISSING', () async {
      final den = File('${tmp.path}/denominator.jsonl');
      _writeJsonl(den, _denominatorLines(families: 3, rowsPerFamily: 3));
      final res = await runPy(
        ws4,
        ['--denominator', den.path, '--out', '${tmp.path}/r.json'],
        environment: {
          'WM4_VENV_PYTHON': '${tmp.path}/no-such-venv-python',
          'WM4_VENV_POLL_SECONDS': '0',
        },
      );
      expect(res.exitCode, 2);
      expect(res.stderr.toString(), contains('VENV_MISSING'));
      expect(File('${tmp.path}/r.json').existsSync(), isFalse);
    }, skip: skipReason);

    test('ws4 REAL run trains arms a-e on a synthetic denominator and '
        'evaluates the frozen PASS bar', () async {
      final den = File('${tmp.path}/denominator.jsonl');
      _writeJsonl(den, _denominatorLines(families: 8, rowsPerFamily: 5));
      final outPath = '${tmp.path}/ws4_report.json';
      final res = await runPy(
          ws4, ['--denominator', den.path, '--out', outPath]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final report =
          jsonDecode(File(outPath).readAsStringSync()) as Map<String, dynamic>;
      expect(report['schema'], 'ws4-report/v1');
      expect(report['propose_only'], isTrue);
      expect(report['banner'].toString(), contains('NEVER certifies'));
      final arms = report['arms'] as Map<String, dynamic>;
      expect(arms.keys.toSet(), {
        'a_logistic', 'b_mlp_matched', 'c_null', 'd_exact_memo',
        'e_ngram_table',
      });
      for (final arm in arms.values.cast<Map<String, dynamic>>()) {
        final metrics = arm['metrics'] as Map<String, dynamic>;
        expect(metrics.keys, containsAll([
          'auc', 'fnr_at_operating_point',
          'evals_skipped_per_false_negative',
        ]));
        expect(arm['operating_point'], isNotNull);
      }
      final passBar = report['pass_bar'] as Map<String, dynamic>;
      expect(passBar['verdict'], anyOf('PASS_BAR_MET', 'FAIL'));
      if (passBar['verdict'] == 'FAIL') {
        expect(passBar['fail_reason'], anyOf('FNR_ABOVE_FLOOR',
            'NOT_BETTER_THAN_CONTROLS', 'HOLDOUT_DEGENERATE'));
      }
      // family-disjointness of the realized split:
      final split =
          (report['provenance'] as Map)['split'] as Map<String, dynamic>;
      expect((split['train_families'] as List)
          .toSet()
          .intersection((split['holdout_families'] as List).toSet()), isEmpty);
      expect((report['provenance'] as Map)['venv'] is Map, isTrue);
    }, skip: venvSkip ?? skipReason);

    // -------------------------------------------------------------------------
    // V-5
    // -------------------------------------------------------------------------

    test('v5 --dry-run plan: floor n, frozen combination rule, operating '
        'point source, writes nothing', () async {
      final sample = File('${tmp.path}/sample.jsonl');
      _writeJsonl(sample, _auditSampleLines(n: 5, calibrated: true));
      final outPath = '${tmp.path}/v5.json';
      final res = await runPy(v5,
          ['--sample', sample.path, '--out', outPath,
           '--operating-threshold', '0.5', '--dry-run']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['sample']['rows'], 5);
      expect(plan['floor']['min_n'], 30);
      expect(plan['floor']['sample_meets_min_n'], isFalse);
      expect(plan['combination_rule'].toString(),
          contains('(ws4_score + ws3_prior_score) / 2'));
      expect(plan['operating_point']['source'], 'ws4_receipt');
      expect(plan['outputs']['named_on_floor_miss'], 'SCREENER_UNCALIBRATED');
      expect(plan['propose_only'], isTrue);
      expect(File(outPath).existsSync(), isFalse);
    }, skip: skipReason);

    test('v5 dry-run refuses a missing sample, NAMED AUDIT_INPUT_MISSING',
        () async {
      final res = await runPy(v5,
          ['--sample', '${tmp.path}/absent.jsonl', '--out', '${tmp.path}/v.json',
           '--dry-run']);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('AUDIT_INPUT_MISSING'));
    }, skip: skipReason);

    test('v5 real run refuses an underpowered sample, NAMED '
        'AUDIT_SAMPLE_TOO_SMALL (no lucky-floor audits)', () async {
      final sample = File('${tmp.path}/small.jsonl');
      _writeJsonl(sample, _auditSampleLines(n: 5, calibrated: true));
      final res = await runPy(v5,
          ['--sample', sample.path, '--out', '${tmp.path}/v.json']);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('AUDIT_SAMPLE_TOO_SMALL'));
      expect(File('${tmp.path}/v.json').existsSync(), isFalse);
    }, skip: skipReason);

    test('v5 REAL run on a calibrated sample: floor satisfied, screener NOT '
        'disabled, ROC + economics recorded', () async {
      final sample = File('${tmp.path}/cal.jsonl');
      _writeJsonl(sample, _auditSampleLines(n: 32, calibrated: true));
      final outPath = '${tmp.path}/cal_report.json';
      final res = await runPy(v5,
          ['--sample', sample.path, '--out', outPath,
           '--operating-threshold', '0.5']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final report =
          jsonDecode(File(outPath).readAsStringSync()) as Map<String, dynamic>;
      expect(report['floor']['satisfied'], isTrue);
      expect(report['screener_disabled'], isFalse);
      expect(report['named'], isNull);
      expect((report['roc'] as List), isNotEmpty);
      expect(report['auc']['screener'], isNotNull);
      final econ = report['economics'] as Map<String, dynamic>;
      expect(econ['full_battery_evals'], 32);
      expect(econ.keys, contains('evals_skipped_per_false_negative'));
      expect(report['propose_only'], isTrue);
      expect(report['banner'].toString(), contains('NEVER certifies'));
    }, skip: skipReason);

    test('v5 REAL run at a bad operating point: NAMED SCREENER_UNCALIBRATED '
        '+ disablement flag (the disablement IS the verdict, exit 0)',
        () async {
      final sample = File('${tmp.path}/uncal.jsonl');
      _writeJsonl(sample, _auditSampleLines(n: 32, calibrated: false));
      final outPath = '${tmp.path}/uncal_report.json';
      final res = await runPy(v5,
          ['--sample', sample.path, '--out', outPath,
           '--operating-threshold', '0.85']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      expect(res.stderr.toString(), contains('SCREENER_UNCALIBRATED'));
      final report =
          jsonDecode(File(outPath).readAsStringSync()) as Map<String, dynamic>;
      expect(report['named'], 'SCREENER_UNCALIBRATED');
      expect(report['screener_disabled'], isTrue);
      expect(report['floor']['satisfied'], isFalse);
      expect(report['kill_clause'].toString(), contains('WS-4/V-5'));
    }, skip: skipReason);

    // -------------------------------------------------------------------------
    // V-6
    // -------------------------------------------------------------------------

    test('v6 --dry-run plan: frozen axes, 16 cells, frozen 3-cell subset, '
        'rust PARITY_PENDING, drift naming, writes nothing', () async {
      final outDir = '${tmp.path}/v6out';
      final res = await runPy(v6, ['--out', outDir, '--dry-run']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['axes'], {
        'quant': ['bf16', '4bit-requant'],
        'template': ['chat', 'raw'],
        'sampler': ['greedy', 't=0.6'],
        'engine': ['python-mlx-lm', 'rust'],
      });
      expect(plan['cells_selected']['count'], 16);
      final subset =
          (plan['frozen_subset_3'] as Map)['ids'] as List;
      expect(subset, [
        'bf16__chat__greedy__python-mlx-lm',
        '4bit-requant__chat__greedy__python-mlx-lm',
        'bf16__chat__t=0.6__python-mlx-lm',
      ]);
      expect(plan['reference_cell'], 'bf16__chat__greedy__python-mlx-lm');
      expect((plan['engine_policy'] as Map)['rust_status'], 'PARITY_PENDING');
      expect(plan['drift_naming'].toString(),
          contains('DRIFT_<FIELD>_<cell_id>'));
      expect(plan['kill_clause'].toString(), contains('do NOT invalidate'));
      final gen = plan['generator'] as Map<String, dynamic>;
      expect(gen['path'].toString(), endsWith('wm_qwen35_generate.py'));
      expect(gen['exists'], isA<bool>());
      // t=0.6 cells carry the presence-penalty protocol note:
      final invocations =
          (plan['cell_invocations'] as List).cast<Map<String, dynamic>>();
      final t06 = invocations
          .firstWhere((c) => (c['cell'] as String).contains('t=0.6'));
      expect(t06['protocol_notes'].toString(),
          contains('PRESENCE_PENALTY_UNSUPPORTED'));
      expect(Directory(outDir).existsSync(), isFalse,
          reason: 'dry-run must not create the out dir');
    }, skip: skipReason);

    test('v6 dry-run KEY LAW: a quant key change selects the frozen 3-cell '
        'subset', () async {
      final kb = File('${tmp.path}/key_before.json')
        ..writeAsStringSync(jsonEncode(_certKey()));
      final ka = File('${tmp.path}/key_after.json')
        ..writeAsStringSync(jsonEncode(_certKey(quant: '4bit-requant')));
      final res = await runPy(v6, [
        '--out', '${tmp.path}/v6out',
        '--key-before', kb.path,
        '--key-after', ka.path,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect((plan['key_comparison'] as Map)['drifted_fields'], ['QUANT']);
      final selected = plan['cells_selected'] as Map<String, dynamic>;
      expect(selected['rule'].toString(),
          contains('key-change-3-cell-subset'));
      expect(selected['ids'], [
        'bf16__chat__greedy__python-mlx-lm',
        '4bit-requant__chat__greedy__python-mlx-lm',
        'bf16__chat__t=0.6__python-mlx-lm',
      ]);
    }, skip: skipReason);

    test('v6 refuses a malformed key file, NAMED KEY_FILE_MALFORMED',
        () async {
      final bad = File('${tmp.path}/key_bad.json');
      final k = _certKey()..remove('engineRev');
      bad.writeAsStringSync(jsonEncode(k));
      final ka = File('${tmp.path}/key_after.json')
        ..writeAsStringSync(jsonEncode(_certKey()));
      final res = await runPy(v6, [
        '--out', '${tmp.path}/v6out',
        '--key-before', bad.path,
        '--key-after', ka.path,
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('KEY_FILE_MALFORMED'));
      expect(res.stderr.toString(), contains('MISSING_FIELD=engineRev'));
    }, skip: skipReason);

    test('v6 refuses half a key pair, NAMED KEY_PAIR_INCOMPLETE', () async {
      final kb = File('${tmp.path}/key_before.json')
        ..writeAsStringSync(jsonEncode(_certKey()));
      final res = await runPy(v6,
          ['--out', '${tmp.path}/v6out', '--key-before', kb.path,
           '--dry-run']);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('KEY_PAIR_INCOMPLETE'));
    }, skip: skipReason);

    test('v6 real run refuses a missing generation callback, NAMED '
        'GENERATOR_MISSING', () async {
      final res = await runPy(v6, [
        '--out', '${tmp.path}/v6out',
        '--generator', '${tmp.path}/no_such_generator.py',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('GENERATOR_MISSING'));
    }, skip: skipReason);

    // -------------------------------------------------------------------------
    // P-2 / P-2b runner
    // -------------------------------------------------------------------------

    test('p2 --dry-run plan: frozen budgets, published constants WITH '
        'citation, comparability banner, pass_bar false, pool status, '
        'blocker checklist, writes nothing', () async {
      final emptyPool = Directory('${tmp.path}/pool')..createSync();
      final outDir = '${tmp.path}/p2out';
      final res = await runPy(p2, [
        '--model', '${tmp.path}/model',
        '--eval-dir', '${tmp.path}/evals',
        '--out', outDir,
        '--variant', 'p2',
        '--pool-dir', emptyPool.path,
        '--offline',
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['budgets'], [10, 25, 50]);
      expect(plan['budgets_frozen'], [10, 25, 50]);
      expect(plan['pass_bar'], isFalse);
      expect(plan['banner'].toString(), contains('NEVER A PASS BAR'));
      final pub =
          (plan['published'] as Map)['accuracy_percent'] as Map<String, dynamic>;
      expect(pub['unedited'],
          {'math500': 7.9, 'gsm8k_test': 13.8, 'ifeval_subset': 21.0});
      expect(pub['10'],
          {'math500': 12.3, 'gsm8k_test': 25.7, 'ifeval_subset': 49.0});
      expect(pub['25'],
          {'math500': 14.1, 'gsm8k_test': 25.1, 'ifeval_subset': 39.9});
      expect(pub['50'],
          {'math500': 48.1, 'gsm8k_test': 67.1, 'ifeval_subset': 62.3});
      expect((plan['published'] as Map)['citation'].toString(),
          contains('lm_understand-logs'));
      expect((plan['published'] as Map)['citation'].toString(),
          contains('RESULTS_excerpt.md'));
      final pool = plan['pool'] as Map<String, dynamic>;
      expect(pool['status'], 'missing');
      expect((pool['refetch'] as Map)['allowed'], isFalse);
      expect((pool['refetch'] as Map)['url_base'].toString(),
          contains('raw.githubusercontent.com/RikiyaT/lm_understand-logs'));
      final blockers =
          (plan['real_run_blockers'] as List).cast<String>();
      expect(blockers, contains('POOL_UNAVAILABLE'));
      expect(blockers, contains('PRACTICE_CMD_MISSING'));
      expect(blockers, contains('SCORER_CLI_MISSING'));
      final protocol = plan['protocol'] as Map<String, dynamic>;
      expect(protocol['our_sampler'], 'greedy');
      expect(protocol['token_cap'], 32768);
      expect(protocol['samples_per_problem'],
          {'math500': 4, 'gsm8k_test': 2, 'ifeval_subset': 2});
      expect(protocol['differences'].toString(),
          contains('SAMPLER_PROTOCOL_DIFFERENCE'));
      expect(protocol['differences'].toString(),
          contains('PRESENCE_PENALTY_UNSUPPORTED'));
      expect(Directory(outDir).existsSync(), isFalse,
          reason: 'dry-run must not create the out dir');
    }, skip: skipReason);

    test('p2 refuses unfrozen budgets even in dry-run, NAMED '
        'BUDGET_NOT_FROZEN', () async {
      final res = await runPy(p2, [
        '--model', '${tmp.path}/model',
        '--eval-dir', '${tmp.path}/evals',
        '--out', '${tmp.path}/p2out',
        '--budgets', '10,20',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('BUDGET_NOT_FROZEN'));
    }, skip: skipReason);

    test('p2 real run offline with a missing pool refuses, NAMED '
        'POOL_UNAVAILABLE (exit 2)', () async {
      final emptyPool = Directory('${tmp.path}/pool')..createSync();
      final res = await runPy(p2, [
        '--model', '${tmp.path}/model',
        '--eval-dir', '${tmp.path}/evals',
        '--out', '${tmp.path}/p2out',
        '--variant', 'p2',
        '--pool-dir', emptyPool.path,
        '--offline',
      ]);
      expect(res.exitCode, 2);
      expect(res.stderr.toString(), contains('POOL_UNAVAILABLE'));
    }, skip: skipReason);

    test('p2 real run offline with a corrupt pool refuses, NAMED '
        'POOL_DIGEST_MISMATCH (exit 1; corrupt data is never used)',
        () async {
      final badPool = Directory('${tmp.path}/badpool')..createSync();
      for (final name in ['README.txt', 'aime.jsonl', 'gsm8k_train.jsonl',
          'math_train.jsonl', 'stats.json']) {
        File('${badPool.path}/$name').writeAsStringSync('garbage\n');
      }
      final res = await runPy(p2, [
        '--model', '${tmp.path}/model',
        '--eval-dir', '${tmp.path}/evals',
        '--out', '${tmp.path}/p2out',
        '--variant', 'p2',
        '--pool-dir', badPool.path,
        '--offline',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('POOL_DIGEST_MISMATCH'));
    }, skip: skipReason);

    test('p2 real run without a p2b pool refuses the p2b variant, NAMED '
        'P2B_POOL_MISSING', () async {
      final res = await runPy(p2, [
        '--model', '${tmp.path}/model',
        '--eval-dir', '${tmp.path}/evals',
        '--out', '${tmp.path}/p2out',
        '--variant', 'p2b',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('P2B_POOL_MISSING'));
    }, skip: skipReason);

    // -------------------------------------------------------------------------
    // P-2b pool builder
    // -------------------------------------------------------------------------

    /// Synthetic pool fixtures; math500 id m2 overlaps after whitespace
    /// normalization; gsm8k test g1 overlaps gsm8k train g1.
    void writeBuilderFixtures() {
      final mt = <String>[];
      for (var i = 0; i < 6; i++) {
        mt.add(jsonEncode({
          'id': 'm$i', 'source': 'math',
          'problem': 'Problem number $i asks  x +$i.',
          'answer': '$i', 'solution': 's',
        }));
      }
      File('${tmp.path}/math_train.jsonl')
          .writeAsStringSync('${mt.join('\n')}\n');
      final m5 = [
        jsonEncode({'id': 'MATH_500_2', 'problem': 'Problem number 2 asks x +2.'}),
        jsonEncode({'id': 'MATH_500_99', 'problem': 'Unseen problem 99.'}),
      ];
      File('${tmp.path}/math500.jsonl').writeAsStringSync('${m5.join('\n')}\n');
      final gt = <String>[];
      for (var i = 0; i < 4; i++) {
        gt.add(jsonEncode(
            {'id': 'g$i', 'question': 'G question $i?', 'answer': '1'}));
      }
      File('${tmp.path}/gsm8k_train.jsonl')
          .writeAsStringSync('${gt.join('\n')}\n');
      final gte = [
        jsonEncode({'id': 't1', 'question': 'G question 1?'}),
        jsonEncode({'id': 't9', 'question': 'G question 9?'}),
      ];
      File('${tmp.path}/gsm8k_test.jsonl')
          .writeAsStringSync('${gte.join('\n')}\n');
    }

    test('p2b --dry-run plan: overlap counts computed read-only, byte '
        'preservation declared, writes nothing', () async {
      writeBuilderFixtures();
      final outDir = '${tmp.path}/p2bout';
      final res = await runPy(p2b, [
        '--math-train', '${tmp.path}/math_train.jsonl',
        '--math500', '${tmp.path}/math500.jsonl',
        '--gsm8k-train', '${tmp.path}/gsm8k_train.jsonl',
        '--gsm8k-test', '${tmp.path}/gsm8k_test.jsonl',
        '--out', outDir,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['overlap_counts'], {
        'math500_removed_from_math_train': 1,
        'gsm8k_test_removed_from_gsm8k_train': 1,
      });
      expect(plan['row_counts']['p2b_math_train'], 5);
      expect(plan['row_counts']['p2b_gsm8k_train'], 3);
      expect(plan['byte_preservation'].toString(), contains('ORIGINAL'));
      expect(plan['distributional_note'].toString(),
          contains('DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED'));
      expect(Directory(outDir).existsSync(), isFalse,
          reason: 'dry-run must not create the out dir');
    }, skip: skipReason);

    test('p2b refuses a missing MATH-500 file, NAMED MATH500_MISSING',
        () async {
      writeBuilderFixtures();
      final res = await runPy(p2b, [
        '--math-train', '${tmp.path}/math_train.jsonl',
        '--math500', '${tmp.path}/absent_math500.jsonl',
        '--out', '${tmp.path}/p2bout',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('MATH500_MISSING'));
    }, skip: skipReason);

    test('p2b refuses half a gsm8k pair, NAMED GSM8K_PAIR_INCOMPLETE',
        () async {
      writeBuilderFixtures();
      final res = await runPy(p2b, [
        '--math-train', '${tmp.path}/math_train.jsonl',
        '--math500', '${tmp.path}/math500.jsonl',
        '--gsm8k-train', '${tmp.path}/gsm8k_train.jsonl',
        '--out', '${tmp.path}/p2bout',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('GSM8K_PAIR_INCOMPLETE'));
    }, skip: skipReason);

    test('p2b refuses a malformed eval jsonl, NAMED INPUT_JSONL_MALFORMED',
        () async {
      writeBuilderFixtures();
      File('${tmp.path}/math500_bad.jsonl')
          .writeAsStringSync('{"id": "x"}\n'); // no problem/question
      final res = await runPy(p2b, [
        '--math-train', '${tmp.path}/math_train.jsonl',
        '--math500', '${tmp.path}/math500_bad.jsonl',
        '--out', '${tmp.path}/p2bout',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('INPUT_JSONL_MALFORMED'));
    }, skip: skipReason);

    test('p2b REAL run builds the strictly-disjoint pool with digest '
        'receipt; overlaps removed and recorded', () async {
      writeBuilderFixtures();
      final outDir = '${tmp.path}/p2bout';
      final res = await runPy(p2b, [
        '--math-train', '${tmp.path}/math_train.jsonl',
        '--math500', '${tmp.path}/math500.jsonl',
        '--gsm8k-train', '${tmp.path}/gsm8k_train.jsonl',
        '--gsm8k-test', '${tmp.path}/gsm8k_test.jsonl',
        '--out', outDir,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final receipt = jsonDecode(
              File('$outDir/build_receipt.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(receipt['schema'], 'p2b-build-receipt/v1');
      expect(receipt['disjointness'], 'PASS');
      expect(receipt['pass_bar'], isFalse);
      expect(receipt['distributional_note'].toString(),
          contains('DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED'));
      final removed = receipt['removed'] as Map<String, dynamic>;
      expect((removed['math500_overlap'] as Map)['count'], 1);
      expect((removed['math500_overlap'] as Map)['ids'], ['m2']);
      expect((removed['gsm8k_test_overlap'] as Map)['ids'], ['g1']);
      // Output rows are the ORIGINAL input bytes; digests verify in Dart.
      final outputs = (receipt['outputs'] as Map).cast<String, dynamic>();
      for (final entry in outputs.entries) {
        final info = entry.value as Map<String, dynamic>;
        final bytes = File(info['path'] as String).readAsBytesSync();
        expect(sha256.convert(bytes).toString(), info['sha256'],
            reason: 'receipt digest must match the built file');
      }
      final mathOut =
          File('$outDir/p2b_math_train.jsonl').readAsLinesSync();
      expect(mathOut.where((l) => l.trim().isNotEmpty).length, 5);
      expect(mathOut.any((l) => l.contains('"m2"')), isFalse);
      final gsmOut =
          File('$outDir/p2b_gsm8k_train.jsonl').readAsLinesSync();
      expect(gsmOut.where((l) => l.trim().isNotEmpty).length, 3);
      expect(receipt['their_pool_stats'], isNotNull);
    }, skip: skipReason);
  });
}
