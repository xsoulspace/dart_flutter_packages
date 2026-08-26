// ignore_for_file: avoid_print

/// Aggregate one or more suite JSONL traces into a comparison report.
///
/// Usage:
///
/// ```
/// dart run benchmark/coding_suite/report.dart trace1.jsonl [trace2.jsonl ...]
/// ```
///
/// Each file becomes one column (label = filename). Prints:
/// - headline per-trace pass rate, tokens, wall clock
/// - per-category pass matrix (traces as columns)
/// - per-task grid for spotting flaky tasks across runs of the same backend
library;

import 'dart:convert';
import 'dart:io';

typedef Row = Map<String, dynamic>;

void main(List<String> args) {
  if (args.isEmpty) {
    print('usage: dart run report.dart <trace.jsonl> [more.jsonl ...]');
    exit(2);
  }

  final traces = <String, List<Row>>{};
  for (final path in args) {
    final rows = <Row>[];
    for (final line in File(path).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        rows.add(jsonDecode(line) as Row);
      } on FormatException {
        // Torn last line from a killed run — skip.
      }
    }
    traces[path.split('/').last] = rows;
  }

  // Headline.
  print('═' * 72);
  for (final entry in traces.entries) {
    final rows = _latestPerTask(entry.value);
    final p = rows.where((r) => r['passed'] == true).length;
    final tok = rows.fold<int>(0, (a, r) => a + (r['tokens_used'] as int));
    final wall = rows.fold<int>(0, (a, r) => a + (r['wall_clock_ms'] as int));
    print(
      '${entry.key.padRight(28)} $p/${rows.length} passed '
      '(${(p / rows.length * 100).toStringAsFixed(0)}%), '
      '~${rows.isEmpty ? 0 : tok ~/ rows.length} tok/task, '
      '${wall ~/ 60000}min wall',
    );
  }
  print('═' * 72);

  // Per-category matrix.
  final categories =
      traces.values
          .expand((rows) => rows.map((r) => r['category'] as String))
          .toSet()
          .toList()
        ..sort();
  print('\nper-category pass rate:');
  final header =
      'category'.padRight(26) +
      traces.keys
          .map((k) => k.substring(0, k.length.clamp(0, 14)).padLeft(15))
          .join();
  print(header);
  for (final cat in categories) {
    final cells = traces.keys.map((k) {
      // Latest occurrence per task within this trace, filtered by category.
      final rows = _latestPerTask(
        traces[k]!,
      ).where((r) => r['category'] == cat).toList();
      if (rows.isEmpty) return '-'.padLeft(15);
      final p = rows.where((r) => r['passed'] == true).length;
      return '$p/${rows.length}'.padLeft(15);
    }).join();
    print(cat.padRight(26) + cells);
  }

  // Flakiness grid when several traces share task ids.
  if (traces.length > 1) {
    final ids =
        traces.values
            .expand((rows) => rows.map((r) => r['task_id'] as String))
            .toSet()
            .toList()
          ..sort();
    print('\nper-task grid (✅/❌):');
    print(
      'task'.padRight(40) +
          traces.keys
              .map((k) => k.substring(0, k.length.clamp(0, 8)).padLeft(9))
              .join(),
    );
    for (final id in ids) {
      final cells = traces.keys.map((k) {
        final match = traces[k]!.where((r) => r['task_id'] == id).toList();
        if (match.isEmpty) return '—'.padLeft(9);
        final last = match.last;
        return ((last['passed'] == true) ? '✅' : '❌').padLeft(9);
      }).join();
      print(id.padRight(40) + cells);
    }
  }

  // Category names come from the loaded spec registry for validation.
  assert(categories.every((c) => c.isNotEmpty), 'category must be non-empty');
}

/// Keep only the latest row per task_id (resume appends; duplicates happen).
List<Row> _latestPerTask(List<Row> rows) {
  final byId = <String, Row>{};
  for (final r in rows) {
    byId[r['task_id'] as String] = r;
  }
  return byId.values.toList();
}
