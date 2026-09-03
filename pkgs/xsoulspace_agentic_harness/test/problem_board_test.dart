// ignore_for_file: lines_longer_than_80_chars

/// ADR 0021 — problems as canonical rows; repairs from project-guided packs.
/// LLM-free: the adapter is syntax-only, the pack is project data, the
/// mechanical tier is a host transform verified by the source analyzer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:agentic_executables_wire/agentic_executables_wire.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/problem_board.dart';

void main() {
  group('adapter: dart analyzer machine format → canonical rows', () {
    test('parses, classifies, skips noise', () {
      final rows = parseDartAnalyzerMachine(const [
        'Analyzing ../..',
        ' WARNING|STATIC_WARNING|UNUSED_IMPORT|file:///w/lib/a.dart|32|8|'
            "Unused import: 'x.dart'.",
        ' INFO|LINT|PREFER_CONST|file:///w/lib/b.dart|9|3|Prefer const',
        '',
        '2 issues found.',
      ]);
      expect(rows, hasLength(2));
      expect(rows[0].classId, 'dart/unused_import');
      expect(rows[0].severity, 'warning');
      expect(rows[0].filePath, '/w/lib/a.dart');
      expect(rows[0].source, 'dart_analyzer');
      expect(rows[1].classId, 'dart/prefer_const');
    });
  });

  group('pack coverage split', () {
    late Directory tempDir;
    setUp(() async =>
        tempDir = await Directory.systemTemp.createTemp('packtest'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('known class → mechanical; unknown class → meaningful tier', () {
      final pack = RepairPackWire.fromJson({
        'packId': 'p',
        'executables': [
          {
            'executableId': 'p/1',
            'classId': 'dart/unused_import',
            'kind': 'delete_line',
          },
        ],
      });
      final rows = [
        ProblemRowWire(
          classId: 'dart/unused_import',
          severity: 'warning',
          filePath: 'a.dart',
          line: 2,
          column: 1,
          message: 'm',
          source: 'dart_analyzer',
        ),
        ProblemRowWire(
          classId: 'dart/custom_thing',
          severity: 'info',
          filePath: 'b.dart',
          line: 5,
          column: 1,
          message: 'm',
          source: 'custom_lint',
        ),
      ];
      final split = splitByPackCoverage(rows, pack);
      expect(split.mechanical, hasLength(1));
      expect(split.mechanical.single.$1.classId, 'dart/unused_import');
      expect(split.meaningful.single.classId, 'dart/custom_thing');
    });

    test('missing pack file → empty pack (everything meaningful, honest)',
        () {
      final pack = loadRepairPack('${tempDir.path}/repair_pack.json');
      expect(pack.executables, isEmpty);
      final split = splitByPackCoverage(
        [
          ProblemRowWire(
            classId: 'dart/unused_import',
            severity: 'warning',
            filePath: 'a.dart',
            line: 2,
            column: 1,
            message: 'm',
            source: 'dart_analyzer',
          ),
        ],
        pack,
      );
      expect(split.mechanical, isEmpty);
      expect(split.meaningful, hasLength(1));
    });
  });

  group('mechanical repair with re-analysis oracle (REAL dart analyze)',
      () {
    late Directory ws;
    setUp(() async {
      ws = await Directory.systemTemp.createTemp('mechrepair');
      // A dart package whose ONLY problem is an unused import: the oracle
      // (dart analyze) is clean iff the import is gone.
      File('${ws.path}/pubspec.yaml').writeAsStringSync(
        'name: mech\nenvironment:\n  sdk: ^3.5.0\ndev_dependencies:\n'
        '  lints: ^5.0.0\n',
      );
      File('${ws.path}/analysis_options.yaml').writeAsStringSync(
        'include: package:lints/recommended.yaml\n',
      );
      Directory('${ws.path}/lib').createSync();
      File('${ws.path}/lib/a.dart').writeAsStringSync(
        "import 'dart:math';\n\nint add(int a, int b) => a + b;\n",
      );
    });
    tearDown(() => ws.deleteSync(recursive: true));

    ProblemRowWire row() => ProblemRowWire(
          classId: 'dart/unused_import',
          severity: 'warning',
          filePath: 'lib/a.dart',
          line: 1,
          column: 1,
          message: "Unused import: 'dart:math'.",
          source: 'dart_analyzer',
        );

    test('delete_line + oracle clean → appliedAndVerified, zero model tokens',
        () async {
      // Prove the problem exists first (the raw source reports it).
      final raw = await Process.run('dart', [
        'analyze',
        '--format=machine',
        'lib/a.dart',
      ], workingDirectory: ws.path);
      expect(parseDartAnalyzerMachine((raw.stdout as String).split('\n')),
          hasLength(1));

      final outcome = await executeMechanicalRepair(
        workspace: ws,
        row: row(),
        executable: const RepairExecutableWire(
          executableId: 'p/1',
          classId: 'dart/unused_import',
          kind: 'delete_line',
        ),
      );
      expect(outcome.kind, RepairOutcomeKind.appliedAndVerified,
          reason: outcome.detail);
      // Minimal literal transform: exactly line 1 removed (the stray blank
      // line stays — conservatism over cosmetics; oracle decides).
      expect(File('${ws.path}/lib/a.dart').readAsStringSync(),
          "\nint add(int a, int b) => a + b;\n");
    });

    test('oracle still failing → REVERTED, original content restored',
        () async {
      // The pack says delete_line, but the file needs its import (a use of
      // dart:math below) — deleting it breaks analysis → revert.
      File('${ws.path}/lib/a.dart').writeAsStringSync(
        "import 'dart:math';\n\nint add(int a, int b) =>\n"
        "    max(a, b) + (a > b ? 0 : 0);\n",
      );
      final outcome = await executeMechanicalRepair(
        workspace: ws,
        row: row(),
        executable: const RepairExecutableWire(
          executableId: 'p/1',
          classId: 'dart/unused_import',
          kind: 'delete_line',
        ),
        oracleArgs: const ['analyze'],
      );
      expect(outcome.kind, RepairOutcomeKind.reverted, reason: outcome.detail);
      expect(File('${ws.path}/lib/a.dart').readAsStringSync(),
          contains("import 'dart:math';"));
    });

    test('unknown executable kind → failed, file untouched', () async {
      final outcome = await executeMechanicalRepair(
        workspace: ws,
        row: row(),
        executable: const RepairExecutableWire(
          executableId: 'p/x',
          classId: 'dart/unused_import',
          kind: 'teleport',
        ),
      );
      expect(outcome.kind, RepairOutcomeKind.failed);
      expect(File('${ws.path}/lib/a.dart').readAsStringSync(),
          contains("import 'dart:math';"));
    });

    test('command kind: project-defined argv runs with span substitution',
        () async {
      // A project-owned "fixer" script (the trust boundary is the project).
      File('${ws.path}/tool_fix.dart').writeAsStringSync(
        "import 'dart:io';\nvoid main(List<String> args) {\n"
        "  final f = File(args.first);\n"
        "  f.writeAsStringSync(f.readAsStringSync()"
        ".replaceFirst(\"import 'dart:math';\", ''));\n}\n",
      );
      final outcome = await executeMechanicalRepair(
        workspace: ws,
        row: row(),
        executable: const RepairExecutableWire(
          executableId: 'p/cmd/1',
          classId: 'dart/unused_import',
          kind: 'command',
          command: ['dart', 'run', 'tool_fix.dart', '{span.file}'],
        ),
      );
      expect(outcome.kind, RepairOutcomeKind.appliedAndVerified,
          reason: outcome.detail);
      expect(File('${ws.path}/lib/a.dart').readAsStringSync(),
          isNot(contains('dart:math')));
    });
  });
}
