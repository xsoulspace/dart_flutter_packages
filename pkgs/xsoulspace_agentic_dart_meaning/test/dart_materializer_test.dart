// ignore_for_file: lines_longer_than_80_chars

/// R6 gate B — the materializer: meaning chains compile to idiomatic
/// workspace Dart that actually executes (real `dart run` subprocess).
/// LLM-free; the model's role is simulated by building chains through the
/// same host-validated define path a scripted/real actor drives.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_dart_meaning/dart_materializer.dart';
import 'package:xsoulspace_agentic_dart_meaning/test_etl.dart';

World _world() => World()..addPlugin(AgentPlugin());

void main() {
  test('compiles a linear arithmetic chain to idiomatic Dart that runs',
      () async {
    final world = _world();
    defineIntent(world, name: 'add', params: ['a:int', 'b:int'], returns: 'int');
    final ids = addChainFromSpecs(world, [
      {'label': 'load_arg', 'a': 'a'},
      {'label': 'load_arg', 'a': 'b'},
      {'label': 'add'},
      {'label': 'return'},
    ]);
    linkMeaning(world, from: 'add', relation: 'impl', to: ids!.first);
    final d = DerivedIntent(
      intent: 'add',
      targetFile: 'lib/calc.dart',
      params: [(name: 'a', type: 'int'), (name: 'b', type: 'int')],
      returns: 'int',
      expectations: const [],
      provenance: const [],
    );
    final mat = materializeWorkspaceDart(world, intents: [d]);
    expect(mat.problems, isEmpty, reason: mat.problems.join('\n'));
    expect(mat.files['lib/calc.dart'], contains('int add(int a, int b) {'));
    expect(mat.files['lib/calc.dart'], contains('return (a + b);'));
    // Execute the generated source for real.
    final dir = await Directory.systemTemp.createTemp('mat_lin_');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    File(
      '${dir.path}/calc.dart',
    ).writeAsStringSync('''
${mat.files['lib/calc.dart']}
void main() {
  if (add(2, 3) != 5) throw StateError('add(2,3)');
  if (add(-1, 1) != 0) throw StateError('add(-1,1)');
  print('OK');
}
''');
    final r = await Process.run(
      'dart',
      ['run', 'calc.dart'],
      workingDirectory: dir.path,
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('compiles jump_if_false chains to structured if/else', () async {
    final world = _world();
    defineIntent(world, name: 'is_adult', params: ['age:int'], returns: 'bool');
    // is_adult = age >= 18. Rows: cond = (age < 18); jump_if_false pops it —
    // FALSE (adult) jumps to literal true; TRUE (minor) falls through to
    // literal false.
    final ids = addChainFromSpecs(world, [
      {'label': 'load_arg', 'a': 'age'},
      {'label': 'literal', 'b': '18'},
      {'label': 'lt'},
      {'label': 'jump_if_false', 'b': '#6'},
      {'label': 'literal', 'b': 'false'},
      {'label': 'return'},
      {'label': 'literal', 'b': 'true'},
      {'label': 'return'},
    ]);
    linkMeaning(world, from: 'is_adult', relation: 'impl', to: ids!.first);
    final d = DerivedIntent(
      intent: 'is_adult',
      targetFile: 'lib/person.dart',
      params: [(name: 'age', type: 'int')],
      returns: 'bool',
      expectations: const [],
      provenance: const [],
    );
    final mat = materializeWorkspaceDart(world, intents: [d]);
    expect(mat.problems, isEmpty, reason: mat.problems.join('\n'));
    final src = mat.files['lib/person.dart']!;
    expect(src, contains('if ((age < 18)) {'));
    expect(src, contains('return false;'));
    expect(src, contains('return true;'));
    final dir = await Directory.systemTemp.createTemp('mat_branch_');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    File(
      '${dir.path}/person.dart',
    ).writeAsStringSync('''
$src
void main() {
  if (!is_adult(20)) throw StateError('is_adult(20)');
  if (is_adult(12)) throw StateError('is_adult(12)');
  print('OK');
}
''');
    final r = await Process.run(
      'dart',
      ['run', 'person.dart'],
      workingDirectory: dir.path,
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('compiles get_item over a list param', () async {
    final world = _world();
    defineIntent(
      world,
      name: 'first_item',
      params: ['items:List<String>'],
      returns: 'String',
    );
    final ids = addChainFromSpecs(world, [
      {'label': 'load_arg', 'a': 'items'},
      {'label': 'literal', 'b': '0'},
      {'label': 'get_item'},
      {'label': 'return'},
    ]);
    linkMeaning(world, from: 'first_item', relation: 'impl', to: ids!.first);
    final d = DerivedIntent(
      intent: 'first_item',
      targetFile: 'lib/first.dart',
      params: [(name: 'items', type: 'List<String>')],
      returns: 'String',
      expectations: const [],
      provenance: const [],
    );
    final mat = materializeWorkspaceDart(world, intents: [d]);
    expect(mat.problems, isEmpty, reason: mat.problems.join('\n'));
    expect(mat.files['lib/first.dart'], contains('return (items[0]);'));
  });

  test('unsupported shapes fail as named problems, never silently', () async {
    final world = _world();
    defineIntent(world, name: 'counts', returns: 'int');
    final ids = addChainFromSpecs(world, [
      {'label': 'push_state', 'a': 'items'},
      {'label': 'return'},
    ]);
    linkMeaning(world, from: 'counts', relation: 'impl', to: ids!.first);
    final d = DerivedIntent(
      intent: 'counts',
      targetFile: 'lib/x.dart',
      params: const [],
      returns: 'int',
      expectations: const [],
      provenance: const [],
    );
    final mat = materializeWorkspaceDart(world, intents: [d]);
    expect(mat.ok, isFalse);
    expect(mat.problems.single, contains('push_state'));
  });
}
