// WS-3 (PREREG-D, frozen) masked-component attribution prior: boundary-script
// self-checks. The dry-run plan must print machine-readable JSON with the
// pre-registered constants (ridge lambda 1e-3, k=3, chance 3/24) WITHOUT
// polling the venv or importing numpy/mlx; bad input must refuse with NAMED
// error codes; the real-run venv gate must poll then fail NAMED VENV_MISSING
// (exercised with env overrides + a zero poll window so no Metal device and
// no model are ever touched - the A3 arm owns the device). The synthetic
// validator must recover the planted layer in top-3 via the SAME scoring
// core the real tool uses.
//
// Skips are NAMED, never silent (repo law). Live captures are NOT run here:
// the integration owner schedules the real WS-3 run.
@Timeout(Duration(seconds: 180))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Walks up from [start] looking for the package marker file.
Directory? _findPackageRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File('${dir.path}/tool/runs/ws3_masked_attribution.py').existsSync()) {
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

bool _pythonAvailable() {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String _venvPython() =>
    '${Platform.environment['HOME']}/.local/share/wm-mlx/bin/python';

void main() {
  final root = _packageRoot();
  final pythonSkip = root == null
      ? 'PACKAGE_ROOT_NOT_FOUND: tool/runs/ws3_masked_attribution.py not '
          'found from cwd or script dir'
      : (_pythonAvailable() ? null : 'PYTHON3_ABSENT: python3 not on PATH');
  final attribution = '${root?.path}/tool/runs/ws3_masked_attribution.py';
  final synthetic = '${root?.path}/tool/runs/ws3_synthetic_validate.py';
  final venvSkip = File(_venvPython()).existsSync()
      ? null
      : 'VENV_MISSING: ${_venvPython()} not found (synthetic validator '
          'needs numpy from the wm-mlx venv)';

  Future<ProcessResult> runPython(
    String script,
    List<String> args, {
    Map<String, String>? environment,
    String? executable,
  }) =>
      Process.run(
        executable ?? 'python3',
        ['-I', script, ...args],
        environment: environment,
        includeParentEnvironment: true,
      );

  group('ws3_masked_attribution dry-run plan', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('weightmap_ws3_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('--dry-run prints the frozen-constant plan, polls no venv, imports '
        'no numpy/mlx, writes nothing', () async {
      final neutral = File('${tmp.path}/neutral.txt')
        ..writeAsStringSync('a neutral prompt\n\nanother neutral\nthird\n');
      final loop = File('${tmp.path}/loop.txt')
        ..writeAsStringSync('loop one\nloop two\n');
      final outPath = '${tmp.path}/ws3.json';
      final res = await runPython(attribution, [
        '--model', '${tmp.path}/model',
        '--neutral-prompts', neutral.path,
        '--loop-prompts', loop.path,
        '--layers', '24',
        '--out', outPath,
        '--dry-run',
      ], environment: {
        // Poison the venv path + zero the poll window: dry-run must NOT care.
        'WM3_VENV_PYTHON': '${tmp.path}/definitely-not-a-python',
        'WM3_VENV_POLL_SECONDS': '0',
      });
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['model'], '${tmp.path}/model');
      expect(plan['layers'], 24);
      expect(plan['layers_masked'], List.generate(24, (i) => i));
      expect(plan['neutral_prompt_count'], 3);
      expect(plan['loop_prompt_count'], 2);
      expect(plan['ridge_lambda'], 1e-3);
      expect(plan['k_top'], 3);
      expect(plan['chance_preregistered'], '3/24');
      expect(plan['prefills_planned'], 25 * 5); // (N+1) passes x prompts
      expect(plan['mlx_imported'], isFalse);
      expect(plan['numpy_imported'], isFalse);
      expect(plan['venv_polled'], isFalse);
      expect(File(outPath).existsSync(), isFalse,
          reason: 'dry-run must not write the summary');
      expect(File('${tmp.path}/ws3.per_layer.jsonl').existsSync(), isFalse,
          reason: 'dry-run must not write the per-layer sidecar');
    }, skip: pythonSkip);

    test('refuses a bad --layers value, NAMED LAYERS_INVALID', () async {
      final neutral = File('${tmp.path}/n.txt')..writeAsStringSync('p\n');
      final loop = File('${tmp.path}/l.txt')..writeAsStringSync('p\n');
      final res = await runPython(attribution, [
        '--model', '${tmp.path}/model',
        '--neutral-prompts', neutral.path,
        '--loop-prompts', loop.path,
        '--layers', 'twenty-four',
        '--out', '${tmp.path}/ws3.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('LAYERS_INVALID'));
    }, skip: pythonSkip);

    test('refuses an empty loop-prompts file, NAMED PROMPTS_EMPTY', () async {
      final neutral = File('${tmp.path}/n.txt')..writeAsStringSync('p\n');
      final loop = File('${tmp.path}/l.txt')..writeAsStringSync('\n  \n');
      final res = await runPython(attribution, [
        '--model', '${tmp.path}/model',
        '--neutral-prompts', neutral.path,
        '--loop-prompts', loop.path,
        '--layers', '24',
        '--out', '${tmp.path}/ws3.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('PROMPTS_EMPTY'));
      expect(res.stderr.toString(), contains('loop'));
    }, skip: pythonSkip);

    test('refuses a missing neutral-prompts file, NAMED '
        'PROMPTS_FILE_UNREADABLE', () async {
      final loop = File('${tmp.path}/l.txt')..writeAsStringSync('p\n');
      final res = await runPython(attribution, [
        '--model', '${tmp.path}/model',
        '--neutral-prompts', '${tmp.path}/absent.txt',
        '--loop-prompts', loop.path,
        '--layers', '24',
        '--out', '${tmp.path}/ws3.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('PROMPTS_FILE_UNREADABLE'));
    }, skip: pythonSkip);

    test('real run without the venv fails NAMED VENV_MISSING after the poll '
        'window (zero-window via env; no mlx, no Metal, no model touched)',
        () async {
      final neutral = File('${tmp.path}/n.txt')..writeAsStringSync('p\n');
      final loop = File('${tmp.path}/l.txt')..writeAsStringSync('p\n');
      final res = await runPython(attribution, [
        '--model', '${tmp.path}/model-does-not-exist',
        '--neutral-prompts', neutral.path,
        '--loop-prompts', loop.path,
        '--layers', '24',
        '--out', '${tmp.path}/ws3.json',
      ], environment: {
        'WM3_VENV_PYTHON': '${tmp.path}/definitely-not-a-python',
        'WM3_VENV_POLL_SECONDS': '0',
      });
      expect(res.exitCode, 2);
      expect(res.stderr.toString(), contains('VENV_MISSING'));
      expect(File('${tmp.path}/ws3.json').existsSync(), isFalse);
    }, skip: pythonSkip);
  });

  group('ws3_synthetic_validate (scoring-core validation, no model)', () {
    test('planted layer recovers into top-3 via the shared scoring core',
        () async {
      final res = await Process.run(
        _venvPython(),
        ['-I', synthetic, '--seed', '20261105', '--planted-layer', '17'],
      );
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final out = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(out['synthetic_validated'], isTrue);
      expect(out['model_used'], isNull,
          reason: 'the synthetic validator must not load any model');
      final top3 = (out['top3'] as List).cast<int>();
      expect(top3, hasLength(3));
      expect(top3, contains(out['planted_layer']));
      expect(out['k'], 3);
      expect(out['n_layers'], 24);
      expect(out['chance_preregistered'], '3/24');
      expect(out['ridge_lambda'], 1e-3);
      for (final control in (out['control_layers_checked'] as List)) {
        expect(top3, isNot(contains(control)),
            reason: 'control layer $control leaked into top-3');
      }
    }, skip: venvSkip);

    test('a second seed also validates (not a lucky draw)', () async {
      final res = await Process.run(
        _venvPython(),
        ['-I', synthetic, '--seed', '7', '--planted-layer', '3'],
      );
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final out = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(out['synthetic_validated'], isTrue);
      expect((out['top3'] as List), contains(3));
    }, skip: venvSkip);
  });
}
