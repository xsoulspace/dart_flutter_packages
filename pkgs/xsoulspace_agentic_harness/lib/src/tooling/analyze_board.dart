// ignore_for_file: lines_longer_than_80_chars

/// Stage N1 — the analyzer task board (LLM-free).
///
/// Parses `dart analyze --format=machine` output and partitions issues into
/// FILE-DISJOINT board tasks. The board IS the problems-discovery artifact:
/// every task carries a mechanical criterion (its file set analyzes clean),
/// so no checker code is ever written per task (D8).
///
/// Machine format (one issue per line, `|`-separated):
/// `SEVERITY|TYPE|ERROR_CODE|FILE_URI|LINE|COLUMN|MESSAGE`
/// Diagnostic/summary lines (`Analyzing`, `issues found`) are skipped.
///
/// Partition rule: one task per file with ≥1 issue. Cross-file coupling
/// (barrel + implementation) is deliberately NOT merged here — that is N5
/// coordination work. First squad tasks must be file-disjoint by design.
library;

import 'dart:io';

/// One analyzer diagnostic, normalized.
class AnalyzeIssue {
  const AnalyzeIssue({
    required this.severity,
    required this.code,
    required this.filePath,
    required this.line,
    required this.column,
    required this.message,
  });

  final String severity;
  final String code;
  final String filePath;
  final int line;
  final int column;
  final String message;

  Map<String, Object?> toJson() => {
    'severity': severity,
    'code': code,
    'file': filePath,
    'line': line,
    'column': column,
    'message': message,
  };
}

/// One board task: the issues of a single file + the mechanical criterion.
class BoardTask {
  const BoardTask({required this.filePath, required this.issues});

  final String filePath;
  final List<AnalyzeIssue> issues;

  /// The goal sentence the claiming actor receives.
  String get prompt {
    final list = [
      for (final i in issues) '- [${i.severity}] line ${i.line}:${i.column} '
          '(${i.code}): ${i.message}',
    ].join('\n');
    return 'Resolve the analyzer issue(s) in ${_rel(filePath)} WITHOUT '
        'changing unrelated code:\n$list\nThe task is done when the check '
        'passes.';
  }

  /// Mechanical criterion: the check command that must exit 0.
  List<String> get checkCommand => ['dart', 'analyze', filePath];

  String _rel(String p) => p.replaceFirst('file://', '');

  Map<String, Object?> toJson() => {
    'file': filePath,
    'criterion': checkCommand,
    'prompt': prompt,
    'issues': [for (final i in issues) i.toJson()],
  };
}

/// Parses `dart analyze --format=machine` lines. Non-conforming lines
/// (progress notes, summaries, blanks) are skipped — never guessed.
List<AnalyzeIssue> parseAnalyzeMachine(Iterable<String> lines) {
  final issues = <AnalyzeIssue>[];
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
    issues.add(
      AnalyzeIssue(
        severity: severity,
        code: parts[2].trim(),
        filePath: parts[3].trim(),
        line: lineNo,
        column: colNo,
        message: parts.sublist(6).join('|').trim(),
      ),
    );
  }
  return issues;
}

/// Groups issues into file-disjoint board tasks (stable order: by file path).
List<BoardTask> buildBoard(List<AnalyzeIssue> issues) {
  final byFile = <String, List<AnalyzeIssue>>{};
  for (final i in issues) {
    byFile.putIfAbsent(i.filePath, () => []).add(i);
  }
  final files = byFile.keys.toList()..sort();
  return [for (final f in files) BoardTask(filePath: f, issues: byFile[f]!)];
}

/// Convenience: run `dart analyze --format=machine` in [cwd] and build the
/// board. Exit code is nonzero when issues exist — expected, not an error.
Future<List<BoardTask>> boardFromAnalyze(
  Directory cwd, {
  List<String> paths = const ['.'],
}) async {
  final result = await Process.run(
    'dart',
    ['analyze', '--format=machine', ...paths],
    workingDirectory: cwd.path,
    stdoutEncoding: const SystemEncoding(),
  );
  final out = result.stdout as String? ?? '';
  return buildBoard(parseAnalyzeMachine(out.split('\n')));
}
