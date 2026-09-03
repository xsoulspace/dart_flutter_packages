// ignore_for_file: lines_longer_than_80_chars

/// ADR 0021 — problems as canonical rows; repairs from project-guided packs.
///
/// This module is the harness-side host over the `problem_wire` contract:
///
/// 1. **Adapter** (generic, syntax-only): Dart analyzer machine-format lines
///    → `ProblemRowWire` rows. One adapter per tool output format; it knows
///    nothing about repairs.
/// 2. **Pack loader**: the project's repair pack (`repair_pack.json` in the
///    workspace root) — PROJECT-GUIDED. The same diagnostic code can warrant
///    different repairs in different projects; custom linters emit custom
///    class ids only the project's pack can map.
/// 3. **Mechanical repair executor**: pack executable + problem row →
///    span transform (or project command) → the SOURCE ANALYZER re-runs as
///    the free oracle → problem closes, or the file reverts and the row
///    escalates to the meaningful tier. Zero model tokens.
///
/// The model never chooses the executable. Rows without a pack entry become
/// meaningful-tier tasks (span-zoom decisions); their resolutions are
/// captured back into the pack — a novel class is resolved ONCE.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show ProblemRowWire, RepairExecutableWire, RepairPackWire;

/// Adapter: Dart analyzer `--format=machine` lines → canonical rows.
/// Non-conforming lines (progress notes, summaries, blanks) are skipped —
/// never guessed. class id convention: `dart/<lowercase-code>`.
List<ProblemRowWire> parseDartAnalyzerMachine(
  Iterable<String> lines, {
  String source = 'dart_analyzer',
}) {
  final rows = <ProblemRowWire>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || !line.contains('|')) continue;
    final parts = line.split('|');
    if (parts.length < 7) continue;
    final severity = parts[0].trim().toUpperCase();
    if (severity != 'ERROR' && severity != 'WARNING' && severity != 'INFO') {
      continue;
    }
    final lineNo = int.tryParse(parts[4].trim());
    final colNo = int.tryParse(parts[5].trim());
    if (lineNo == null || colNo == null) continue;
    rows.add(
      ProblemRowWire(
        classId: 'dart/${parts[2].trim().toLowerCase()}',
        severity: severity.toLowerCase(),
        filePath: _projectRelative(parts[3].trim()),
        line: lineNo,
        column: colNo,
        message: parts.sublist(6).join('|').trim(),
        source: source,
      ),
    );
  }
  return rows;
}

String _projectRelative(String uriOrPath) =>
    uriOrPath.replaceFirst('file://', '');

/// Loads the project's repair pack from [path] (JSON). Missing file → an
/// empty pack (every row goes to the meaningful tier — honest, never guessed).
RepairPackWire loadRepairPack(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    return const RepairPackWire(packId: 'empty', executables: []);
  }
  final decoded = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
  return RepairPackWire.fromJson(decoded);
}

/// The outcome of one mechanical repair attempt.
enum RepairOutcomeKind { appliedAndVerified, reverted, noExecutable, failed }

class RepairOutcome {
  const RepairOutcome({
    required this.row,
    required this.kind,
    required this.detail,
  });
  final ProblemRowWire row;
  final RepairOutcomeKind kind;
  final String detail;
}

/// Groups rows by pack coverage: mechanical candidates vs meaningful-tier
/// tasks (no executable). Pure.
({List<(ProblemRowWire, RepairExecutableWire)> mechanical,
List<ProblemRowWire> meaningful})
splitByPackCoverage(List<ProblemRowWire> rows, RepairPackWire pack) {
  final mechanical = <(ProblemRowWire, RepairExecutableWire)>[];
  final meaningful = <ProblemRowWire>[];
  for (final row in rows) {
    final executable = pack.forClass(row.classId);
    if (executable == null) {
      meaningful.add(row);
    } else {
      mechanical.add((row, executable));
    }
  }
  return (mechanical: mechanical, meaningful: meaningful);
}

/// Executes one mechanical repair and verifies with the SOURCE ANALYZER
/// (the oracle that reported the problem is the oracle that closes it).
/// Any verification failure reverts the file — a wrong mechanical fix is
/// worse than an escalation.
Future<RepairOutcome> executeMechanicalRepair({
  required Directory workspace,
  required ProblemRowWire row,
  required RepairExecutableWire executable,
  String oracleBinary = 'dart',
  List<String> oracleArgs = const ['analyze'],
  Duration oracleTimeout = const Duration(seconds: 120),
}) async {
  final file = File('${workspace.path}/${row.filePath}');
  if (!file.existsSync()) {
    return RepairOutcome(
      row: row,
      kind: RepairOutcomeKind.failed,
      detail: 'file not found: ${row.filePath}',
    );
  }
  final original = file.readAsStringSync();
  final lines = original.split('\n');

  switch (executable.kind) {
    case 'delete_line':
      if (row.line < 1 || row.line > lines.length) {
        return RepairOutcome(
          row: row,
          kind: RepairOutcomeKind.failed,
          detail: 'line ${row.line} out of range (${lines.length} lines)',
        );
      }
      lines.removeAt(row.line - 1);
      file.writeAsStringSync(lines.join('\n'));
    case 'replace_span':
      final idx = row.line - 1;
      if (idx < 0 || idx >= lines.length) {
        return RepairOutcome(
          row: row,
          kind: RepairOutcomeKind.failed,
          detail: 'line ${row.line} out of range',
        );
      }
      lines[idx] = executable.replacement ?? '';
      file.writeAsStringSync(lines.join('\n'));
    case 'command':
      final argv = [
        for (final token in executable.command ?? const <String>[])
          token
              .replaceAll('{span.file}', row.filePath)
              .replaceAll('{span.line}', '${row.line}'),
      ];
      final proc = await Process.run(
        argv.first,
        argv.sublist(1),
        workingDirectory: workspace.path,
      ).timeout(const Duration(minutes: 5));
      if (proc.exitCode != 0) {
        return RepairOutcome(
          row: row,
          kind: RepairOutcomeKind.failed,
          detail: 'repair command exit=${proc.exitCode}: ${proc.stderr}',
        );
      }
    default:
      return RepairOutcome(
        row: row,
        kind: RepairOutcomeKind.failed,
        detail: 'unknown executable kind: ${executable.kind}',
      );
  }

  // ORACLE: the source analyzer re-runs. Clean → the problem closed.
  try {
    final oracle = await Process.run(
      oracleBinary,
      [...oracleArgs, row.filePath],
      workingDirectory: workspace.path,
    ).timeout(oracleTimeout);
    if (oracle.exitCode == 0) {
      return RepairOutcome(
        row: row,
        kind: RepairOutcomeKind.appliedAndVerified,
        detail: 'oracle clean',
      );
    }
  } on Object {
    // fall through to revert
  }
  // Verification failed → revert. A wrong mechanical fix is worse than an
  // escalation.
  file.writeAsStringSync(original);
  return RepairOutcome(
    row: row,
    kind: RepairOutcomeKind.reverted,
    detail: 'oracle still failing — repair reverted, escalate to meaningful '
        'tier',
  );
}
