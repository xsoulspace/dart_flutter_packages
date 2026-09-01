// ignore_for_file: lines_longer_than_80_chars

/// Stage N1 — analyzer task board: machine-format parsing, file-disjoint
/// partitioning, mechanical criteria. LLM-free.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/analyze_board.dart';

void main() {
  test('parses machine lines, skips progress/summary/blank noise', () {
    final issues = parseAnalyzeMachine(const [
      'Analyzing ../..',
      ' ERROR|COMPILE_TIME_ERROR|URI_DOES_NOT_EXIST|file:///w/lib/a.dart|3|7|Target of URI doesn\'t exist',
      ' WARNING|STATIC_TYPE_WARNING|UNUSED_IMPORT|file:///w/lib/a.dart|1|8|Unused import',
      ' INFO|LINT|PREFER_CONST|file:///w/lib/b.dart|9|3|Prefer const',
      '',
      '3 issues found.',
    ]);
    expect(issues, hasLength(3));
    expect(issues[0].severity, 'ERROR');
    expect(issues[0].code, 'URI_DOES_NOT_EXIST');
    expect(issues[0].line, 3);
    expect(issues[2].filePath, 'file:///w/lib/b.dart');
    expect(issues[2].message, contains('Prefer const'));
  });

  test('buildBoard partitions by file, disjoint, stable order', () {
    final issues = parseAnalyzeMachine(const [
      ' ERROR|X|CODE1|file:///w/lib/b.dart|1|1|m1',
      ' ERROR|X|CODE2|file:///w/lib/a.dart|2|1|m2',
      ' INFO|X|CODE3|file:///w/lib/a.dart|3|1|m3',
    ]);
    final board = buildBoard(issues);
    expect(board, hasLength(2));
    expect(board[0].filePath, 'file:///w/lib/a.dart');
    expect(board[0].issues, hasLength(2));
    expect(board[1].filePath, 'file:///w/lib/b.dart');
    // Disjointness: no file appears in two tasks.
    final files = [for (final t in board) t.filePath];
    expect(files.toSet(), hasLength(files.length));
  });

  test('task prompt carries the issues; criterion is dart analyze on the file',
      () {
    final issues = parseAnalyzeMachine(const [
      ' WARNING|X|UNUSED_IMPORT|file:///w/lib/a.dart|1|8|Unused import',
    ]);
    final task = buildBoard(issues).single;
    expect(task.checkCommand, const ['dart', 'analyze', 'file:///w/lib/a.dart']);
    expect(task.prompt, contains('UNUSED_IMPORT'));
    expect(task.prompt, contains('line 1:8'));
  });

  test('boardFromAnalyze runs the real analyzer on a dirty fixture', () async {
    final dir = await Directory.systemTemp.createTemp('n1_board');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/bad.dart').writeAsStringSync(
      "void main() {\n  var x = 1\n  print(x);\n}\n",
    );
    final board = await boardFromAnalyze(dir, paths: ['bad.dart']);
    // Machine format must yield at least the missing-semicolon diagnostic.
    expect(board, isNotEmpty);
    expect(jsonEncode(board.first.toJson()), contains('bad.dart'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
