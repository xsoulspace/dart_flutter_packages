import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// PREREG-A arm A1 — mechanical edit audit tooling test.
///
/// Builds tiny 2-shard safetensors fixtures (F32, hand-rolled headers, no
/// third-party python deps) into Directory.systemTemp via
/// `python3 -I test/tool/make_fixture_safetensors.py`, then exercises:
///
///   * diff_safetensors.py — RESULT_DIFF (exit 1) with the planted single
///     differing tensor and its exact element count in the jsonl receipt;
///     RESULT_IDENTICAL (exit 0) on a self-diff; NAMED refusals (exit 2)
///     for MALFORMED_HEADER and SHARD_MISSING.
///   * sha256_verify.py — MATCH (exit 0), SHA256_MISMATCH (exit 1), and
///     NAMED FILE_MISSING / BAD_EXPECTED_HEX refusals (exit 2).
///
/// If python3 cannot be executed, every test skips with the NAMED reason
/// PYTHON3_UNAVAILABLE — never silently. No network is touched.
const _package = 'xsoulspace_inference_weightmap';

const _shard1 = 'model-00001-of-00002.safetensors';
const _shard2 = 'model-00002-of-00002.safetensors';

Directory _packageRoot() {
  for (final root in [Directory.current, Directory('pkgs/$_package')]) {
    if (File('${root.path}/tool/audit/diff_safetensors.py').existsSync()) {
      return Directory(root.resolveSymbolicLinksSync());
    }
  }
  throw StateError(
    'PACKAGE_ROOT_UNRESOLVED: run from the package root or the repository '
    'root (marker tool/audit/diff_safetensors.py not found).',
  );
}

String? _python3OrNull() {
  try {
    final probe = Process.runSync('python3', ['--version']);
    if (probe.exitCode == 0) return 'python3';
  } on ProcessException catch (_) {
    // fall through to the named skip
  } on OSError catch (_) {
    // fall through to the named skip
  }
  return null;
}

void main() {
  final python3 = _python3OrNull();
  final skip = python3 == null
      ? 'PYTHON3_UNAVAILABLE: python3 could not be executed (Process.run '
          'failed); audit tooling tests need it'
      : null;
  final root = _packageRoot();
  final diffScript = '${root.path}/tool/audit/diff_safetensors.py';
  final shaScript = '${root.path}/tool/audit/sha256_verify.py';
  final fixtureScript = '${root.path}/test/tool/make_fixture_safetensors.py';

  ProcessResult runPython(String script, List<String> args) =>
      Process.runSync(python3!, ['-I', script, ...args]);

  Directory? tempRoot;
  late Directory dirA;
  late Directory dirB;
  var n = 0; // printed by the fixture builder as diffing_elements=N

  setUpAll(() {
    if (python3 == null) return; // every test carries the NAMED skip below
    final tmp =
        Directory.systemTemp.createTempSync('weightmap_audit_test.');
    tempRoot = tmp;
    dirA = Directory('${tmp.path}/A');
    dirB = Directory('${tmp.path}/B');
    final fixture = runPython(fixtureScript, [dirA.path, dirB.path]);
    expect(
      fixture.exitCode,
      0,
      reason: 'FIXTURE_BUILD_FAILED: ${fixture.stderr}',
    );
    final match = RegExp(r'^diffing_elements=(\d+)$', multiLine: true)
        .firstMatch(fixture.stdout as String);
    expect(
      match,
      isNotNull,
      reason: 'DIFFING_ELEMENTS_UNNAMED: fixture stdout lacks '
          'diffing_elements=N: ${fixture.stdout}',
    );
    n = int.parse(match!.group(1)!);
    expect(n, greaterThan(0));
  });

  tearDownAll(() {
    final tmp = tempRoot;
    if (tmp != null && tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('diff_safetensors.py', () {
    test('planted fixture: exactly 1 differing tensor, N elements, exit 1 '
        '(RESULT_DIFF) with a jsonl receipt', () {
      final receiptPath = '${tempRoot!.path}/receipt.jsonl';
      final result = runPython(
        diffScript,
        [dirA.path, dirB.path, '--receipt', receiptPath],
      );
      expect(
        result.exitCode,
        1,
        reason: 'expected RESULT_DIFF exit 1; stderr=${result.stderr}',
      );

      // stdout carries ONLY the summary line.
      final stdoutLines = const LineSplitter()
          .convert((result.stdout as String).trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(stdoutLines, hasLength(1));
      final summary = jsonDecode(stdoutLines.single) as Map<String, dynamic>;
      expect(summary['tensors_differing'], 1);
      expect(summary['elements_differing'], n);
      expect(summary['inventory_match'], isTrue);

      // Both shards hashed per side; shard 1 identical, shard 2 edited.
      final files = (summary['files'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(files, hasLength(2));
      final byName = {for (final f in files) f['file'] as String: f};
      expect(byName[_shard1]!['sha256_a'], byName[_shard1]!['sha256_b']);
      expect(
        byName[_shard2]!['sha256_a'],
        isNot(byName[_shard2]!['sha256_b']),
      );

      // Receipt: one tensor line, then the same summary line.
      final receiptLines = const LineSplitter()
          .convert(File(receiptPath).readAsStringSync())
          .where((line) => line.isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(receiptLines, hasLength(2));
      final tensorLine = receiptLines.first;
      expect(tensorLine['tensor'], 'mlp.down_proj.weight');
      expect(tensorLine['shape'], [8, 16]);
      expect(tensorLine['dtype'], 'F32');
      expect(tensorLine['differing_elements'], n);
      expect(tensorLine['reason'], 'ELEMENT_DIFF');
      expect(receiptLines.last, summary);
    });

    test('self-diff: exit 0 (RESULT_IDENTICAL), zero differing tensors', () {
      final result = runPython(diffScript, [dirA.path, dirA.path]);
      expect(
        result.exitCode,
        0,
        reason: 'expected RESULT_IDENTICAL exit 0; stderr=${result.stderr}',
      );
      final summary =
          jsonDecode((result.stdout as String).trim()) as Map<String, dynamic>;
      expect(summary['tensors_differing'], 0);
      expect(summary['elements_differing'], 0);
      expect(summary['inventory_match'], isTrue);
    });

    test('malformed header is refused with NAMED MALFORMED_HEADER, exit 2',
        () {
      final bad = Directory('${tempRoot!.path}/bad_header')..createSync();
      final shard = File('${bad.path}/model.safetensors')
        ..writeAsBytesSync(File('${dirA.path}/$_shard1').readAsBytesSync());
      // Corrupt the 8-byte little-endian header-length prefix.
      final raf = shard.openSync(mode: FileMode.writeOnly);
      raf.writeFromSync(List<int>.filled(8, 0xff));
      raf.closeSync();

      final result = runPython(diffScript, [bad.path, dirA.path]);
      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('MALFORMED_HEADER'));
    });

    test('index naming an absent shard is refused with NAMED SHARD_MISSING, '
        'exit 2', () {
      final partial = Directory('${tempRoot!.path}/missing_shard')..createSync();
      File('${dirA.path}/$_shard1')
          .copySync('${partial.path}/$_shard1');
      File('${dirA.path}/model.safetensors.index.json')
          .copySync('${partial.path}/model.safetensors.index.json');
      // $_shard2 deliberately absent but named by the index.

      final result = runPython(diffScript, [partial.path, dirA.path]);
      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('SHARD_MISSING'));
    });
  }, skip: skip);

  group('sha256_verify.py', () {
    late String shard1Path;
    late String shard1Sha;

    setUp(() {
      shard1Path = '${dirA.path}/$_shard1';
      shard1Sha = sha256
          .convert(File(shard1Path).readAsBytesSync())
          .toString();
    });

    test('correct digest: MATCH, exit 0', () {
      final result = runPython(shaScript, [shard1Path, shard1Sha]);
      expect(result.exitCode, 0);
      expect((result.stdout as String).trim(), 'MATCH $shard1Sha');
    });

    test('wrong digest: NAMED SHA256_MISMATCH with both digests, exit 1', () {
      final wrong = (shard1Sha.startsWith('0') ? '1' : '0') +
          shard1Sha.substring(1);
      final result = runPython(shaScript, [shard1Path, wrong]);
      expect(result.exitCode, 1);
      final stdout = (result.stdout as String).trim();
      expect(stdout, contains('SHA256_MISMATCH'));
      expect(stdout, contains('expected=$wrong'));
      expect(stdout, contains('actual=$shard1Sha'));
    });

    test('absent file: NAMED FILE_MISSING, exit 2', () {
      final result = runPython(
        shaScript,
        ['${tempRoot!.path}/does_not_exist.bin', shard1Sha],
      );
      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('FILE_MISSING'));
    });

    test('non-hex expected digest: NAMED BAD_EXPECTED_HEX, exit 2', () {
      final result = runPython(shaScript, [shard1Path, 'not-a-digest']);
      expect(result.exitCode, 2);
      expect(result.stderr as String, contains('BAD_EXPECTED_HEX'));
    });
  }, skip: skip);
}
