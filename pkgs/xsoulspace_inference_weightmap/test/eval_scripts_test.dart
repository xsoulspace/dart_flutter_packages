// Boundary-script self-checks: both tool/eval Python scripts run with
// `python3 -I`, dry-run to exit 0 with a machine-readable plan, and refuse
// bad input with NAMED error codes (never silent). The apply_delta real run
// is exercised against a synthetic safetensors shard in $TMPDIR (probe
// scratch law) and must leave the base byte-identical.
//
// If python3 or the package root is unavailable the tests SKIP with a named
// reason (repo law: skips are named, never silent).
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// Walks up from [start] looking for the package marker file.
Directory? _findPackageRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File('${dir.path}/tool/eval/apply_delta.py').existsSync()) return dir;
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

/// Minimal valid safetensors file: 8-byte LE header length + json header +
/// zero-filled data. Pure bytes; no tooling needed to build it.
Uint8List _syntheticSafetensors(String tensorName,
    {required int rows, required int cols}) {
  final header = jsonEncode({
    tensorName: {
      'dtype': 'F32',
      'shape': [rows, cols],
      'data_offsets': [0, rows * cols * 4],
    },
  });
  final headerBytes = utf8.encode(header);
  final builder = BytesBuilder();
  final lengthBytes = ByteData(8)..setUint64(0, headerBytes.length, Endian.little);
  builder.add(lengthBytes.buffer.asUint8List());
  builder.add(headerBytes);
  builder.add(List<int>.filled(rows * cols * 4, 0));
  return builder.toBytes();
}

void main() {
  final root = _packageRoot();
  final skipReason = root == null
      ? 'PACKAGE_ROOT_NOT_FOUND: tool/eval/apply_delta.py not found from cwd '
          'or script dir'
      : (_pythonAvailable() ? null : 'PYTHON3_ABSENT: python3 not on PATH');
  final captureScript = '${root?.path}/tool/eval/capture_activations.py';
  final applyScript = '${root?.path}/tool/eval/apply_delta.py';

  Future<ProcessResult> runPython(String script, List<String> args) =>
      Process.run('python3', ['-I', script, ...args]);

  group('tool/eval boundary scripts', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('weightmap_eval_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('capture_activations --dry-run prints the plan, imports no mlx, '
        'writes nothing', () async {
      final prompts = File('${tmp.path}/prompts.txt')
        ..writeAsStringSync('first prompt\n\nsecond prompt\n');
      final outPath = '${tmp.path}/act.json';
      final res = await runPython(captureScript, [
        '--model', '${tmp.path}/model',
        '--prompts', prompts.path,
        '--layers', '15,19',
        '--out', outPath,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan =
          jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['model'], '${tmp.path}/model');
      expect(plan['layers'], [15, 19]);
      expect(plan['prompt_count'], 2);
      expect(plan['mlx_imported'], isFalse);
      expect(File(outPath).existsSync(), isFalse,
          reason: 'dry-run must not write the artifact');
    }, skip: skipReason);

    test('capture_activations dry-run expands layer ranges', () async {
      final prompts = File('${tmp.path}/prompts.txt')..writeAsStringSync('p\n');
      final res = await runPython(captureScript, [
        '--model', '${tmp.path}/model',
        '--prompts', prompts.path,
        '--layers', '0-2,15',
        '--out', '${tmp.path}/act.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['layers'], [0, 1, 2, 15]);
      expect(plan['prompt_count'], 1);
    }, skip: skipReason);

    test('capture_activations refuses a bad layer spec, NAMED', () async {
      final prompts = File('${tmp.path}/prompts.txt')..writeAsStringSync('p\n');
      final res = await runPython(captureScript, [
        '--model', '${tmp.path}/model',
        '--prompts', prompts.path,
        '--layers', 'fifteen',
        '--out', '${tmp.path}/act.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('LAYER_SPEC_INVALID'));
    }, skip: skipReason);

    test('capture_activations refuses an empty prompts file, NAMED', () async {
      final prompts = File('${tmp.path}/prompts.txt')..writeAsStringSync('\n \n');
      final res = await runPython(captureScript, [
        '--model', '${tmp.path}/model',
        '--prompts', prompts.path,
        '--layers', '15',
        '--out', '${tmp.path}/act.json',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('PROMPTS_EMPTY'));
    }, skip: skipReason);

    test('apply_delta --dry-run validates spec shape, SKIPS the base read, '
        'writes nothing', () async {
      final specFile = File('${tmp.path}/spec.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 'model.layers.15.mlp.down_proj.weight',
          'columns': [3, 7],
          'direction': [0.5, 0.25, -0.5, 1.0],
          'scale': 2.0,
        }));
      final outDir = '${tmp.path}/out';
      final res = await runPython(applyScript, [
        '--base', '${tmp.path}/base-does-not-exist',
        '--spec', specFile.path,
        '--out', outDir,
        '--dry-run',
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final plan = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(plan['mode'], 'dry-run');
      expect(plan['applied_rank'], 2);
      expect(plan['base_read'].toString(), contains('SKIPPED'));
      expect(plan['spec_digest'],
          sha256.convert(utf8.encode(specFile.readAsStringSync())).toString());
      expect(Directory(outDir).existsSync(), isFalse,
          reason: 'dry-run must not create the out dir');
    }, skip: skipReason);

    test('apply_delta refuses a bad spec shape, NAMED SPEC_SHAPE_MISMATCH',
        () async {
      final specFile = File('${tmp.path}/bad_spec.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 't.weight',
          'columns': 'not-a-list',
          'direction': [1.0],
          'scale': 1.0,
        }));
      final res = await runPython(applyScript, [
        '--base', tmp.path,
        '--spec', specFile.path,
        '--out', '${tmp.path}/out',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('SPEC_SHAPE_MISMATCH'));
      expect(res.stderr.toString(), contains('columns'));
    }, skip: skipReason);

    test('apply_delta refuses an unknown key and a missing key, NAMED',
        () async {
      final specFile = File('${tmp.path}/extra_spec.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 't.weight',
          'columns': [1],
          'direction': [1.0],
          'scale': 1.0,
          'extra': true, // strict frozen shape: extra keys refuse
        }));
      final res = await runPython(applyScript, [
        '--base', tmp.path,
        '--spec', specFile.path,
        '--out', '${tmp.path}/out',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('SPEC_SHAPE_MISMATCH'));
    }, skip: skipReason);

    test('apply_delta refuses malformed json, NAMED SPEC_READ_ERROR', () async {
      final specFile = File('${tmp.path}/junk_spec.json')
        ..writeAsStringSync('not json {');
      final res = await runPython(applyScript, [
        '--base', tmp.path,
        '--spec', specFile.path,
        '--out', '${tmp.path}/out',
        '--dry-run',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('SPEC_READ_ERROR'));
    }, skip: skipReason);

    test('apply_delta real run writes the sidecar + receipt and NEVER mutates '
        'the base', () async {
      final baseDir = Directory('${tmp.path}/base')..createSync();
      final shard = File('${baseDir.path}/model.safetensors')
        ..writeAsBytesSync(
            _syntheticSafetensors('t.weight', rows: 4, cols: 8));
      final specFile = File('${tmp.path}/spec.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 't.weight',
          'columns': [1, 3],
          'direction': [0.5, 0.25, -0.5, 1.0],
          'scale': 2.0,
        }));
      final baseDigestBefore =
          sha256.convert(await shard.readAsBytes()).toString();
      final outDir = '${tmp.path}/out';

      final res = await runPython(applyScript, [
        '--base', baseDir.path,
        '--spec', specFile.path,
        '--out', outDir,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');

      final receiptFile = File('$outDir/receipt.json');
      expect(receiptFile.existsSync(), isTrue);
      final receipt =
          jsonDecode(await receiptFile.readAsString()) as Map<String, dynamic>;
      expect(receipt['base_dir'], baseDir.path);
      expect(receipt['spec_digest'],
          sha256.convert(await specFile.readAsBytes()).toString());
      expect(receipt['applied_rank'], 2);
      expect(receipt['tensor'], 't.weight');
      expect(receipt['tensor_shape'], [4, 8]);
      expect(receipt['base_read_only'], isTrue);

      final outFiles = (receipt['out_files'] as List).cast<String>();
      expect(outFiles, contains('receipt.json'));
      // numpy present -> delta.npz; numpy absent -> documented delta.json
      // fallback named in the receipt. Either way the artifact exists.
      final artifact = receipt['artifact'] as String;
      expect(artifact, receipt['numpy_available'] == true
          ? 'delta.npz'
          : 'delta.json');
      expect(outFiles, contains(artifact));
      for (final name in outFiles) {
        expect(File('$outDir/$name').existsSync(), isTrue,
            reason: 'receipt lists a missing file: $name');
      }
      if (artifact == 'delta.json') {
        final delta =
            jsonDecode(await File('$outDir/delta.json').readAsString())
                as Map<String, dynamic>;
        expect((delta['column_deltas'] as Map).keys.toList(), ['1', '3']);
        expect((delta['column_deltas'] as Map)['1'], [1.0, 0.5, -1.0, 2.0]);
      }

      final baseDigestAfter =
          sha256.convert(await shard.readAsBytes()).toString();
      expect(baseDigestAfter, baseDigestBefore,
          reason: 'the base shard must be byte-identical after the run');
    }, skip: skipReason);

    test('apply_delta real run refuses a tensor absent from the base, NAMED '
        'TENSOR_NOT_FOUND', () async {
      final baseDir = Directory('${tmp.path}/base2')..createSync();
      File('${baseDir.path}/model.safetensors').writeAsBytesSync(
          _syntheticSafetensors('other.weight', rows: 4, cols: 8));
      final specFile = File('${tmp.path}/spec2.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 'missing.weight',
          'columns': [0],
          'direction': [1.0, 2.0, 3.0, 4.0],
          'scale': 1.0,
        }));
      final res = await runPython(applyScript, [
        '--base', baseDir.path,
        '--spec', specFile.path,
        '--out', '${tmp.path}/out2',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('TENSOR_NOT_FOUND'));
    }, skip: skipReason);

    test('apply_delta real run refuses a direction/shape mismatch, NAMED '
        'SPEC_SHAPE_MISMATCH', () async {
      final baseDir = Directory('${tmp.path}/base3')..createSync();
      File('${baseDir.path}/model.safetensors')
          .writeAsBytesSync(_syntheticSafetensors('t.weight', rows: 4, cols: 8));
      final specFile = File('${tmp.path}/spec3.json')
        ..writeAsStringSync(jsonEncode({
          'tensor': 't.weight',
          'columns': [0],
          'direction': [1.0, 2.0], // 2 != 4 rows
          'scale': 1.0,
        }));
      final res = await runPython(applyScript, [
        '--base', baseDir.path,
        '--spec', specFile.path,
        '--out', '${tmp.path}/out3',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('SPEC_SHAPE_MISMATCH'));
      expect(res.stderr.toString(), contains('direction length'));
    }, skip: skipReason);
  });
}
