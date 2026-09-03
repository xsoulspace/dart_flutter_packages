// ignore_for_file: lines_longer_than_80_chars

/// R6 gate A — the ETL-in derivation: the workspace's OWN suite becomes the
/// expectation table (zero host-authored expectations). LLM-free.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_dart_meaning/test_etl.dart';

Future<Directory> _fixture({
  required String testBody,
  required String libBody,
}) async {
  final dir = await Directory.systemTemp.createTemp('etl_fixture_');
  addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
  File('${dir.path}/test/calc_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(testBody);
  if (libBody.isNotEmpty) {
    File('${dir.path}/lib/calc.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(libBody);
  }
  return dir;
}

void main() {
  test('derives intent skeleton + expectations from a failing suite', () async {
    final ws = await _fixture(
      testBody: '''
import 'package:calc_jail/calc.dart';
import 'package:test/test.dart';
void main() {
  test('add returns the sum', () {
    expect(add(2, 3), 5);
  });
  test('add handles negatives', () {
    expect(add(-1, 1), 0);
  });
}
''',
      libBody: 'int add(int a, int b) {\n  return 0;\n}\n',
    );
    final d = deriveWorkspaceIntents(ws);
    expect(d.intents, hasLength(1));
    final add = d.intents.single;
    expect(add.intent, 'add');
    expect(add.targetFile, 'lib/calc.dart');
    expect(add.returns, 'int');
    expect(add.params, hasLength(2));
    expect(add.params[0], (name: 'a', type: 'int'));
    expect(add.params[1], (name: 'b', type: 'int'));
    expect(add.expectations, hasLength(2));
    expect(add.expectations[0].args, {'a': 2, 'b': 3});
    expect(add.expectations[0].expect, {'value': 5});
    expect(add.expectations[1].args, {'a': -1, 'b': 1});
    expect(add.expectations[1].expect, {'value': 0});
    // Provenance: every expectation cites the test line it came from.
    expect(add.provenance, everyElement(contains('calc_test.dart:')));
  });

  test('derives from equals() matcher, strings, and multi-arg calls',
      () async {
    final ws = await _fixture(
      testBody: '''
import 'package:calc_jail/calc.dart';
void main() {
  expect(greet('Ada'), equals('hi Ada'));
  expect(answer(), 42);
}
''',
      libBody: "String greet(String name) => '';\nint answer() => 0;\n",
    );
    final d = deriveWorkspaceIntents(ws);
    expect(d.intents, hasLength(2));
    final greet = d.intents.firstWhere((i) => i.intent == 'greet');
    expect(greet.expectations.single.args, {'name': 'Ada'});
    expect(greet.expectations.single.expect, {'value': 'hi Ada'});
    expect(greet.returns, 'String');
    final answer = d.intents.firstWhere((i) => i.intent == 'answer');
    expect(answer.params, isEmpty);
  });

  test('unresolvable rows are honest data, never dropped', () async {
    final ws = await _fixture(
      testBody: '''
void main() {
  expect(add(2, someVariable), 5);
  expect(mystery(1), 2);
}
''',
      libBody: 'int add(int a, int b) => 0;\n',
    );
    final d = deriveWorkspaceIntents(ws);
    // 'add' with a non-literal arg is unresolvable; 'mystery' has no subject.
    expect(d.intents, isEmpty);
    expect(d.unresolved, hasLength(1));
    expect(d.unresolved.single, contains('mystery'));
  });

  test('a workspace with no test/ directory fails honestly (D8)', () async {
    final dir = await Directory.systemTemp.createTemp('etl_notests_');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    expect(() => deriveWorkspaceIntents(dir), throwsStateError);
  });
}
