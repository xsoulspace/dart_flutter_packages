// wm_qwen35_* boundary-script tests — DRY-RUN PATHS ONLY, no MLX venv
// needed (the scripts import mlx at runtime, after every named refusal).
//
// Covers, per the work order:
//   1. --dry-run plan text for generate/digest/bench (JSON on stdout,
//      exit 0, "mlx_imported": false, arch + prompt count from the fake
//      config/prompts files).
//   2. NAMED refusal ARCH_UNSUPPORTED (exit 2) with a fake non-qwen3_5
//      config — on both the dry-run and the real path (the arch check
//      runs before the mlx import).
//   3. VENV_MISSING (exit 2) from wm_pyenv.sh with HOME overridden to an
//      empty temp dir; the refusal must carry the uv creation commands.
//
// Run from the package dir: dart test test/wm_qwen35_scripts_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Directory _findPackageRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: xsoulspace_inference_mlx_native')) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('package root not found from ${Directory.current.path}');
}

void main() {
  final root = _findPackageRoot();
  final nursery = '${root.path}/tool/nursery';

  late Directory tmp;
  late String modelOk;
  late String modelBad;
  late String prompts;

  setUpAll(() {
    // System python3 is enough: dry-run and refusals are stdlib-only.
    final probe = Process.runSync('python3', ['--version']);
    if (probe.exitCode != 0) {
      markTestSkipped('python3 not on PATH');
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wm_qwen35_scripts_test_');
    modelOk = '${tmp.path}/model_ok';
    Directory(modelOk).createSync(recursive: true);
    File('$modelOk/config.json').writeAsStringSync(jsonEncode({
      'model_type': 'qwen3_5',
      'architectures': ['Qwen3_5ForConditionalGeneration'],
      'text_config': {'model_type': 'qwen3_5_text', 'num_hidden_layers': 24},
    }));
    modelBad = '${tmp.path}/model_bad';
    Directory(modelBad).createSync(recursive: true);
    File('$modelBad/config.json').writeAsStringSync(jsonEncode({
      'model_type': 'llama',
      'architectures': ['LlamaForCausalLM'],
    }));
    prompts = '${tmp.path}/prompts.txt';
    File(prompts).writeAsStringSync('Hello world\n\nThe capital of France is\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult py(String script, List<String> args) =>
      Process.runSync('python3', ['$nursery/$script', ...args]);

  Map<String, dynamic> dryPlan(ProcessResult r) {
    expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
    return jsonDecode((r.stdout as String).trim()) as Map<String, dynamic>;
  }

  group('dry-run plans', () {
    test('generate prints the plan without importing mlx', () {
      final plan = dryPlan(py('wm_qwen35_generate.py', [
        '--model', modelOk,
        '--prompts', prompts,
        '--max-tokens', '8',
        '--out', '${tmp.path}/out.jsonl',
        '--dry-run',
      ]));
      expect(plan['script'], 'wm_qwen35_generate.py');
      expect(plan['arch'], 'qwen3_5');
      expect(plan['prompt_count'], 2); // blank line skipped
      expect(plan['max_tokens'], 8);
      expect(plan['sampler'], 'greedy');
      expect(plan['mlx_imported'], isFalse);
    });

    test('digest prints the plan with digest_steps', () {
      final plan = dryPlan(py('wm_qwen35_digest.py', [
        '--model', modelOk,
        '--prompts', prompts,
        '--max-tokens', '24',
        '--out', '${tmp.path}/digest.json',
        '--dry-run',
      ]));
      expect(plan['arch'], 'qwen3_5');
      expect(plan['prompt_count'], 2);
      expect(plan['digest_steps'], 8);
      expect(plan['mlx_imported'], isFalse);
    });

    test('bench prints the plan from --prompt-count', () {
      final plan = dryPlan(py('wm_qwen35_bench.py', [
        '--model', modelOk,
        '--prompt-count', '4',
        '--max-tokens', '128',
        '--out', '${tmp.path}/bench.json',
        '--dry-run',
      ]));
      expect(plan['arch'], 'qwen3_5');
      expect(plan['prompt_count'], 4);
      expect(plan['mlx_imported'], isFalse);
    });
  });

  group('ARCH_UNSUPPORTED', () {
    test('real path refuses a non-qwen3_5 config before any mlx import', () {
      final r = py('wm_qwen35_generate.py', [
        '--model', modelBad,
        '--prompts', prompts,
        '--max-tokens', '8',
        '--out', '${tmp.path}/out.jsonl',
      ]);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('ARCH_UNSUPPORTED'));
      expect(r.stderr as String, contains('llama'));
    });

    test('dry-run refuses too (arch check precedes the plan)', () {
      final r = py('wm_qwen35_digest.py', [
        '--model', modelBad,
        '--prompts', prompts,
        '--max-tokens', '8',
        '--out', '${tmp.path}/digest.json',
        '--dry-run',
      ]);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('ARCH_UNSUPPORTED'));
      expect(r.stderr as String, contains('llama'));
    });

    test('missing model dir is MODEL_DIR_MISSING, not a crash', () {
      final r = py('wm_qwen35_bench.py', [
        '--model', '${tmp.path}/nope',
        '--prompt-count', '1',
        '--max-tokens', '8',
        '--out', '${tmp.path}/bench.json',
        '--dry-run',
      ]);
      expect(r.exitCode, 2);
      expect(r.stderr as String, contains('MODEL_DIR_MISSING'));
    });
  });

  group('wm_pyenv.sh', () {
    test('VENV_MISSING with an empty HOME carries the uv commands', () {
      final fakeHome = '${tmp.path}/fakehome';
      Directory(fakeHome).createSync(recursive: true);
      final r = Process.runSync(
        'bash',
        ['$nursery/wm_pyenv.sh'],
        environment: {'HOME': fakeHome, 'WM_MLX_VENV_DIR': ''},
      );
      expect(r.exitCode, 2);
      final err = r.stderr as String;
      expect(err, contains('VENV_MISSING'));
      expect(err, contains('uv venv'));
      expect(err, contains('uv pip install'));
      expect(err, contains(fakeHome));
    });
  });
}
