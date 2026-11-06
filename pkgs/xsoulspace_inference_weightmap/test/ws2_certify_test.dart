// WS-2 certification glue: tool/runs/ws2_certify.py runs with `python3 -I`
// (stdlib only), certifies fixture digest bundles against the SAME frozen
// rulebook lib/src/cross_engine.dart implements (Python-first roles,
// edge-inclusive tolerance, named mismatch vocabulary), and journals one
// jsonl line per run. Operational failures refuse with NAMED codes on stderr
// and exit 1; a MISMATCH verdict is a measured finding (exit 0, journaled).
//
// Fixture bundles live under $TMPDIR (probe scratch law). If python3 or the
// package root is unavailable the tests SKIP with a named reason (repo law:
// skips are named, never silent).
@Timeout(Duration(seconds: 120))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Walks up from [start] looking for the package marker file.
Directory? _findPackageRoot(Directory start) {
  var dir = start;
  while (true) {
    if (File('${dir.path}/tool/runs/ws2_certify.py').existsSync()) return dir;
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

Map<String, Object?> _cell(String name, double value,
        {String logits = 'logits-digest', String behavior = 'behavior-digest'}) =>
    {
      'cell': name,
      'logits_digest': logits,
      'behavior_digest': behavior,
      'behavior_value': value,
    };

void main() {
  final root = _packageRoot();
  final skipReason = root == null
      ? 'PACKAGE_ROOT_NOT_FOUND: tool/runs/ws2_certify.py not found from cwd '
          'or script dir'
      : (_pythonAvailable() ? null : 'PYTHON3_ABSENT: python3 not on PATH');
  final certifyScript = '${root?.path}/tool/runs/ws2_certify.py';
  final certifyWrapper = '${root?.path}/tool/runs/ws2_certify.sh';

  Future<ProcessResult> runCertify(List<String> args) =>
      Process.run('python3', ['-I', certifyScript, ...args]);

  group('tool/runs/ws2_certify.py', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('weightmap_ws2_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Writes a bundle/tolerance fixture and returns its path.
    String write(String name, Object? json) {
      final f = File('${tmp.path}/$name')..writeAsStringSync(jsonEncode(json));
      return f.path;
    }

    String writeBundle(String name, String engine, List<Object?> cells) =>
        write(name, {'engine': engine, 'cells': cells});

    String writeTolerance(String name, {num abs = 0.01, num rel = 0}) =>
        write(name, {'abs': abs, 'rel': rel});

    /// The frozen record line(s) appended to [outPath].
    List<Map<String, Object?>> outLines(String outPath) =>
        File(outPath)
            .readAsLinesSync()
            .map((l) => Map<String, Object?>.from(jsonDecode(l) as Map))
            .toList();

    test('AGREE case: within the pre-registered bound, journaled as one '
        'jsonl line', () async {
      final pyFile = writeBundle('py.json', 'python_mlxlm', [
        _cell('g0-task', 0.80, logits: 'py-a'),
        _cell('g2-loop-rate', 0.30, logits: 'py-b'),
      ]);
      final rustFile = writeBundle('rust.json', 'rust', [
        _cell('g0-task', 0.805, logits: 'rs-a'),
        _cell('g2-loop-rate', 0.295, logits: 'rs-b'),
      ]);
      final tolFile = writeTolerance('tol.json');
      final out = '${tmp.path}/ws2.jsonl';

      final res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', out,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final lines = outLines(out);
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line['tool'], 'ws2_certify.py');
      expect(line['verdict'], 'AGREE');
      expect(line['reference_engine'], 'python_mlxlm');
      expect(line['candidate_engine'], 'rust');
      expect(line['cells_compared'], 2);
      expect(line['logits_bitwise_equal'], 0); // digests key, numbers decide
      expect(line['mismatches'], isEmpty);
      expect((line['tolerance']! as Map)['abs'], 0.01);
      expect((line['tolerance']! as Map)['rel'], 0);
      expect(line['created_utc'], isA<String>());
      // stdout echoes the same record.
      expect(jsonDecode(res.stdout as String), equals(line));
    }, skip: skipReason);

    test('tolerance edge is INCLUSIVE in python too: at the edge agrees, one '
        'float step beyond mismatches', () async {
      final tolFile = writeTolerance('edge_tol.json', abs: 0.25, rel: 0);
      final atEdgeRust = writeBundle('at_edge_rust.json', 'rust',
          [_cell('c', 0.75)]);
      final pastEdgeRust = writeBundle('past_edge_rust.json', 'rust',
          [_cell('c', 0.7500000000000001)]);
      final pyFile =
          writeBundle('edge_py.json', 'python_mlxlm', [_cell('c', 0.5)]);

      final atOut = '${tmp.path}/at_edge.jsonl';
      final at = await runCertify([
        '--rust-digest', atEdgeRust,
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', atOut,
      ]);
      expect(at.exitCode, 0, reason: '${at.stdout}\n${at.stderr}');
      expect(outLines(atOut).single['verdict'], 'AGREE');

      final pastOut = '${tmp.path}/past_edge.jsonl';
      final past = await runCertify([
        '--rust-digest', pastEdgeRust,
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', pastOut,
      ]);
      expect(past.exitCode, 0);
      final pastLine = outLines(pastOut).single;
      expect(pastLine['verdict'], 'MISMATCH');
      expect((pastLine['mismatches']! as List).single['reason'],
          'BEHAVIOR_DELTA_OUT_OF_TOLERANCE');
    }, skip: skipReason);

    test('MISMATCH case names the offending cell, exit stays 0 (a mismatch '
        'is a finding, not a tool failure)', () async {
      final pyFile = writeBundle('mm_py.json', 'python_mlxlm', [
        _cell('g0-task', 0.80),
        _cell('g2-loop-rate', 0.30),
      ]);
      final rustFile = writeBundle('mm_rust.json', 'rust', [
        _cell('g0-task', 0.80), // agrees
        _cell('g2-loop-rate', 0.45), // 0.15 past the 0.01 bound
      ]);
      final out = '${tmp.path}/mm.jsonl';
      final res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', writeTolerance('mm_tol.json'),
        '--out', out,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final line = outLines(out).single;
      expect(line['verdict'], 'MISMATCH');
      expect(line['cells_compared'], 2);
      final mismatches = (line['mismatches']! as List).cast<Map>();
      expect(mismatches, hasLength(1));
      expect(mismatches.single['cell'], 'g2-loop-rate');
      expect(mismatches.single['reason'], 'BEHAVIOR_DELTA_OUT_OF_TOLERANCE');
      final detail = mismatches.single['detail'] as String;
      expect(detail, contains('expected(python_mlxlm)=0.3'));
      expect(detail, contains('actual(rust)=0.45'));
    }, skip: skipReason);

    test('cell-set drift is named per side', () async {
      final pyFile = writeBundle('cs_py.json', 'python_mlxlm', [
        _cell('shared', 0.5),
        _cell('only-in-python', 0.25),
      ]);
      final rustFile = writeBundle('cs_rust.json', 'rust', [
        _cell('shared', 0.5),
        _cell('only-in-rust', 0.25),
      ]);
      final out = '${tmp.path}/cs.jsonl';
      final res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', writeTolerance('cs_tol.json'),
        '--out', out,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      final line = outLines(out).single;
      expect(line['verdict'], 'MISMATCH');
      expect(line['cells_compared'], 1);
      final byCell = {
        for (final m in (line['mismatches']! as List).cast<Map>())
          m['cell']: m['reason'],
      };
      expect(byCell['only-in-python'], 'CELL_MISSING_IN_CANDIDATE');
      expect(byCell['only-in-rust'], 'CELL_MISSING_IN_REFERENCE');
    }, skip: skipReason);

    test('jsonl append law: every run leaves a durable row (denominator)',
        () async {
      final pyFile = writeBundle('ap_py.json', 'python_mlxlm', [_cell('c', 0.5)]);
      final rustFile = writeBundle('ap_rust.json', 'rust', [_cell('c', 0.5)]);
      final tolFile = writeTolerance('ap_tol.json');
      final out = '${tmp.path}/appended.jsonl';
      final args = [
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', out,
      ];
      expect((await runCertify(args)).exitCode, 0);
      expect((await runCertify(args)).exitCode, 0);
      final lines = outLines(out);
      expect(lines, hasLength(2));
      expect(lines.every((l) => l['verdict'] == 'AGREE'), isTrue);
    }, skip: skipReason);

    test('swapped engines refuse with NAMED ENGINE_PAIR_INVALID and write '
        'nothing', () async {
      // The --py-digest file carries engine=rust: roles contradict the flags.
      final wrongPy = writeBundle('wrong_py.json', 'rust', [_cell('c', 0.5)]);
      final rustFile = writeBundle('p_rust.json', 'rust', [_cell('c', 0.5)]);
      final out = '${tmp.path}/never.jsonl';
      final res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', wrongPy,
        '--tolerance', writeTolerance('p_tol.json'),
        '--out', out,
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('ENGINE_PAIR_INVALID'));
      expect(res.stderr.toString(), contains('Python-first'));
      expect(File(out).existsSync(), isFalse,
          reason: 'an operational refusal writes no record');
    }, skip: skipReason);

    test('malformed bundles refuse with NAMED MALFORMED_BUNDLE', () async {
      final rustFile = writeBundle('mb_rust.json', 'rust', [_cell('c', 0.5)]);
      final tolFile = writeTolerance('mb_tol.json');
      // Missing engine key.
      final noEngine = write('mb_no_engine.json', {
        'cells': [_cell('c', 0.5)],
      });
      var res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', noEngine,
        '--tolerance', tolFile,
        '--out', '${tmp.path}/mb1.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('MALFORMED_BUNDLE'));
      expect(res.stderr.toString(), contains('keys mismatch'));
      expect(res.stderr.toString(), contains('engine'));
      // behavior_value of the wrong type (bool is not a number).
      final badValue = writeBundle('mb_bad_value.json', 'python_mlxlm', [
        {
          'cell': 'c',
          'logits_digest': 'l',
          'behavior_digest': 'b',
          'behavior_value': true,
        },
      ]);
      res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', badValue,
        '--tolerance', tolFile,
        '--out', '${tmp.path}/mb2.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('MALFORMED_BUNDLE'));
      expect(res.stderr.toString(), contains('behavior_value'));
      // Unknown engine.
      final unknown = writeBundle('mb_unknown.json', 'tensorflow', [_cell('c', 0.5)]);
      res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', unknown,
        '--tolerance', tolFile,
        '--out', '${tmp.path}/mb3.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('ENGINE_UNKNOWN=tensorflow'));
    }, skip: skipReason);

    test('missing or unreadable files refuse with NAMED read errors', () async {
      final pyFile =
          writeBundle('rd_py.json', 'python_mlxlm', [_cell('c', 0.5)]);
      final tolFile = writeTolerance('rd_tol.json');
      // Missing rust bundle.
      var res = await runCertify([
        '--rust-digest', '${tmp.path}/does_not_exist.json',
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', '${tmp.path}/rd1.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('BUNDLE_READ_ERROR'));
      // Bundle that is not valid json.
      final junk = File('${tmp.path}/junk.json')..writeAsStringSync('not json {');
      res = await runCertify([
        '--rust-digest', junk.path,
        '--py-digest', pyFile,
        '--tolerance', tolFile,
        '--out', '${tmp.path}/rd2.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('BUNDLE_READ_ERROR'));
      expect(res.stderr.toString(), contains('not valid json'));
      // Missing tolerance file.
      final rustFile = writeBundle('rd_rust.json', 'rust', [_cell('c', 0.5)]);
      res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', '${tmp.path}/no_tol.json',
        '--out', '${tmp.path}/rd3.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('TOLERANCE_READ_ERROR'));
    }, skip: skipReason);

    test('an invalid tolerance refuses with NAMED TOLERANCE_INVALID (no '
        'default epsilon)', () async {
      final pyFile =
          writeBundle('ti_py.json', 'python_mlxlm', [_cell('c', 0.5)]);
      final rustFile = writeBundle('ti_rust.json', 'rust', [_cell('c', 0.5)]);
      // Negative bound.
      var res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', write('ti_neg.json', {'abs': -0.01, 'rel': 0}),
        '--out', '${tmp.path}/ti1.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('TOLERANCE_INVALID'));
      // Missing rel: the bound is pre-registered data, never defaulted.
      res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', write('ti_partial.json', {'abs': 0.01}),
        '--out', '${tmp.path}/ti2.jsonl',
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('TOLERANCE_INVALID'));
      expect(res.stderr.toString(), contains('rel'));
    }, skip: skipReason);

    test('an unwritable --out refuses with NAMED OUT_UNWRITABLE', () async {
      final pyFile =
          writeBundle('ow_py.json', 'python_mlxlm', [_cell('c', 0.5)]);
      final rustFile = writeBundle('ow_rust.json', 'rust', [_cell('c', 0.5)]);
      final dirAsOut = Directory('${tmp.path}/i-am-a-dir')..createSync();
      final res = await runCertify([
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', writeTolerance('ow_tol.json'),
        '--out', dirAsOut.path,
      ]);
      expect(res.exitCode, 1);
      expect(res.stderr.toString(), contains('OUT_UNWRITABLE'));
    }, skip: skipReason);

    test('the sh wrapper execs the same certifier', () async {
      if (!File(certifyWrapper).existsSync()) {
        markTestSkipped('WRAPPER_ABSENT: tool/runs/ws2_certify.sh not found');
        return;
      }
      final pyFile =
          writeBundle('sh_py.json', 'python_mlxlm', [_cell('c', 0.5)]);
      final rustFile = writeBundle('sh_rust.json', 'rust', [_cell('c', 0.5)]);
      final out = '${tmp.path}/sh.jsonl';
      final res = await Process.run('/bin/sh', [
        certifyWrapper,
        '--rust-digest', rustFile,
        '--py-digest', pyFile,
        '--tolerance', writeTolerance('sh_tol.json'),
        '--out', out,
      ]);
      expect(res.exitCode, 0, reason: '${res.stdout}\n${res.stderr}');
      expect(outLines(out).single['verdict'], 'AGREE');
    }, skip: skipReason);
  });
}
