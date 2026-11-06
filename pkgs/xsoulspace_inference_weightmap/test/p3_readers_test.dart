// P-3 localization-bench script self-checks (PREREG-D §P-3):
// all four tool/runs scripts run in --dry-run mode (plan only, NO network, NO
// numpy import, NO writes) via Process.run, and refuse missing artifacts with
// NAMED error codes when pointed at an empty temp dir. Dry-run gates are
// stdlib-only by design, so the system python3 (no numpy) is sufficient.
//
// If python3, bash or the package root is unavailable the tests SKIP with a
// named reason (repo law: skips are named, never silent).
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Walks up from [start] looking for the package marker file.
Directory? _findPackageRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File('${dir.path}/tool/runs/p3_exp1_reader.py').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

Directory? _packageRoot() =>
    _findPackageRoot(Directory.current) ??
    _findPackageRoot(Directory(Platform.script.toFilePath()).parent);

bool _have(String exe) {
  try {
    return Process.runSync(exe, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Files each script's dry-run presence gate requires, relative to the
/// artifacts dir. Touched as EMPTY files: dry-run checks existence only and
/// never parses npz/manifest content.
const _exp1Files = [
  'exp1_which_game/networks/0bbcc3ea.npz',
  'exp1_which_game/networks/a9f535cc.npz',
  'exp1_which_game/networks/bdf99279.npz',
  'exp1_which_game/networks/dfc6cb65.npz',
  'exp1_which_game/eval/answer_key.json',
];
const _exp2Files = [
  'exp2_diffusion/networks/246a5b58.npz',
  'exp2_diffusion/networks/a6a9dfb7.npz',
  'exp2_diffusion/networks/d88aba69.npz',
  'exp2_diffusion/networks/training/circle_s0.json',
  'exp2_diffusion/networks/training/square_s0.json',
  'exp2_diffusion/networks/training/triangle_s0.json',
  'exp2_diffusion/eval/answer_key.json',
];
const _exp3Files = [
  'exp3_language/python_dataset/files.tsv',
  'exp3_language/python_dataset/corpus_sha256.txt',
  'exp3_language/python_dataset/packages.txt',
  'exp3_language/python_dataset/rebuild_from_manifest.py',
  'exp3_language/python_dataset/stats.json',
  'exp3_language/python_dataset/scripts/tinylm/data.py',
  'exp3_language/python_dataset/scripts/tinylm2/data_big.py',
  'exp3_language/eval/heads.json',
];

void _touchAll(Directory root, List<String> rel) {
  for (final r in rel) {
    final f = File('${root.path}/$r');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('');
  }
}

void main() {
  final root = _packageRoot();
  final python = _have('python3') ? 'python3' : null;
  final bash = _have('bash') ? 'bash' : null;
  final skipReason = root == null
      ? 'PACKAGE_ROOT_NOT_FOUND: tool/runs/p3_exp1_reader.py not found from '
          'cwd or script dir'
      : (python == null ? 'PYTHON3_ABSENT: python3 not on PATH' : null);
  final fetchScript = '${root?.path}/tool/runs/p3_fetch.sh';
  final exp1Script = '${root?.path}/tool/runs/p3_exp1_reader.py';
  final exp2Script = '${root?.path}/tool/runs/p3_exp2_reader.py';
  final exp3Script = '${root?.path}/tool/runs/p3_exp3_heads.py';

  Future<ProcessResult> runPy(String script, List<String> args) =>
      Process.run(python!, ['-I', script, ...args]);

  group('P-3 dry-run gates (plan only, no network)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('weightmap_p3_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('p3_fetch.sh --dry-run prints the fetch plan, no network', () async {
      final res = await Process.run(bash!, [fetchScript, '--dry-run']);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['network'], isFalse);
      expect(plan['file_count'], 29);
      expect((plan['files'] as List), contains(
          'exp1_which_game/eval/answer_key.json'));
      expect((plan['files'] as List), contains(
          'exp3_language/python_dataset/rebuild_from_manifest.py'));
      // deliberate non-fetches stay non-fetched (label-leak / scope guards)
      expect((plan['files'] as List).join(' '),
          isNot(contains('samples')),
          reason: 'exp2 rendered samples would leak labels');
      expect((plan['files'] as List).join(' '),
          isNot(contains('blocks.npz')),
          reason: 'exp3 model reading is out of scope this run');
      expect(Directory('${tmp.path}/p3-artifacts').existsSync(), isFalse,
          reason: 'dry-run must not create the dest');
    }, skip: bash == null ? 'BASH_ABSENT: bash not on PATH' : skipReason);

    test('exp1 reader dry-run refuses an absent artifacts dir, NAMED '
        'ARTIFACTS_DIR_MISSING', () async {
      final res = await runPy(exp1Script, [
        '--artifacts', '${tmp.path}/nope',
        '--out', '${tmp.path}/exp1.jsonl',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('ARTIFACTS_DIR_MISSING'));
      expect(File('${tmp.path}/exp1.jsonl').existsSync(), isFalse);
    }, skip: skipReason);

    test('exp1 reader dry-run refuses an empty artifacts dir, NAMED '
        'EXP1_NETS_MISSING', () async {
      Directory('${tmp.path}/empty').createSync();
      final res = await runPy(exp1Script, [
        '--artifacts', '${tmp.path}/empty',
        '--out', '${tmp.path}/exp1.jsonl',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('EXP1_NETS_MISSING'));
      expect(res.stderr.toString(), contains('0bbcc3ea.npz'));
    }, skip: skipReason);

    test('exp1 reader dry-run with all artifacts present prints the frozen '
        'plan, imports no numpy, writes nothing', () async {
      final art = Directory('${tmp.path}/art1')..createSync();
      _touchAll(art, _exp1Files);
      final outPath = '${tmp.path}/exp1.jsonl';
      final res = await runPy(exp1Script, [
        '--artifacts', art.path,
        '--out', outPath,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['network'], isFalse);
      expect(plan['numpy_imported'], isFalse);
      expect(plan['frozen_rule_sha256'], isA<String>());
      expect((plan['frozen_rule_sha256'] as String).length, 64);
      expect(plan['frozen_rule'].toString(), contains('R1'));
      expect(File(outPath).existsSync(), isFalse,
          reason: 'dry-run must not write the results file');
    }, skip: skipReason);

    test('exp2 reader dry-run refuses an empty artifacts dir, NAMED '
        'EXP2_NETS_MISSING', () async {
      Directory('${tmp.path}/empty2').createSync();
      final res = await runPy(exp2Script, [
        '--artifacts', '${tmp.path}/empty2',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('EXP2_NETS_MISSING'));
    }, skip: skipReason);

    test('exp2 reader dry-run plans a NO_KEY_EXP2 named skip when the key is '
        'absent but nets are present', () async {
      final art = Directory('${tmp.path}/art2')..createSync();
      _touchAll(art, _exp2Files.sublist(0, 3)); // nets only, no key
      final res = await runPy(exp2Script, [
        '--artifacts', art.path,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['key_present'], isFalse);
      expect(plan['no_key_plan'], 'NO_KEY_EXP2 named skip');
      expect(plan['numpy_imported'], isFalse);
      expect(plan['frozen_rule'].toString(), contains('area_ratio'));
    }, skip: skipReason);

    test('exp2 reader dry-run with key present plans scoring at chance 1/3',
        () async {
      final art = Directory('${tmp.path}/art2b')..createSync();
      _touchAll(art, _exp2Files);
      final res = await runPy(exp2Script, [
        '--artifacts', art.path,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['key_present'], isTrue);
      expect(plan['no_key_plan'], isNull);
      expect((plan['plan'] as Map)['chance'], closeTo(1 / 3, 1e-9));
    }, skip: skipReason);

    test('exp3 heads dry-run refuses an absent artifacts dir, NAMED '
        'ARTIFACTS_DIR_MISSING', () async {
      final res = await runPy(exp3Script, [
        '--artifacts', '${tmp.path}/nope3',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('ARTIFACTS_DIR_MISSING'));
    }, skip: skipReason);

    test('exp3 heads dry-run refuses an empty artifacts dir, NAMED '
        'MANIFEST_MISSING', () async {
      Directory('${tmp.path}/empty3').createSync();
      final res = await runPy(exp3Script, [
        '--artifacts', '${tmp.path}/empty3',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('MANIFEST_MISSING'));
      expect(res.stderr.toString(), contains('files.tsv'));
    }, skip: skipReason);

    test('exp3 heads dry-run with the manifest present prints the phased '
        'plan, runs no subprocess, writes nothing', () async {
      final art = Directory('${tmp.path}/art3')..createSync();
      _touchAll(art, _exp3Files);
      final outPath = '${tmp.path}/exp3.jsonl';
      final rebuildOut = '${tmp.path}/rebuild';
      final res = await runPy(exp3Script, [
        '--artifacts', art.path,
        '--out', outPath,
        '--rebuild-out', rebuildOut,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['network'], isFalse);
      expect(plan['numpy_imported'], isFalse);
      expect(plan['subprocess_run'], isFalse);
      expect((plan['plan'] as Map)['phases'],
          containsAll(['R-A_manifest_integrity', 'R-B_rebuild_attempt',
            'R-C_claimed_heads_parse',
            'R-D/R-E_detector_synthetic_validation']));
      expect((plan['plan'] as Map)['claimed_cutoff'], 0.2);
      expect(File(outPath).existsSync(), isFalse);
      expect(Directory(rebuildOut).existsSync(), isFalse,
          reason: 'dry-run must not create the rebuild dir');
    }, skip: skipReason);
  });
}
