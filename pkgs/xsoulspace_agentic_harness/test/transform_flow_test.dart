// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

void main() {
  late Directory jail;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('transform-flow-test');
    final f = File('${jail.path}/lib/main.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync('void main() {\n  runApp();\n}\n');
  });

  tearDown(() => jail.delete(recursive: true));

  TransformContext ctx() => TransformContext(jail.path);

  test('anchor patch: unique anchor → validated op → applied', () {
    const anchor = 'runApp();';
    final stage = AnchorStage('lib/main.dart', anchor)
      ..fileMissing('file_missing')
      ..notUnique('anchor_not_unique')
      ..thenReplace('runApp(debug: true);');
    final results = TransformFlow([stage]).evaluate(ctx());
    expect(results.single, isA<EmitOp>());
    final report = applyOps(jail.path, results);
    expect(report.applied, 1);
    expect(report.failed, 0);
    expect(
      File('${jail.path}/lib/main.dart').readAsStringSync(),
      contains('runApp(debug: true);'),
    );
    expect(report.tokenCost, lessThan(10));
  });

  test('ambiguous anchor fails BEFORE any mutation, with counts+hint', () {
    final d = File('${jail.path}/lib/dup.dart')..createSync(recursive: true);
    d.writeAsStringSync('x();\nx();\n');
    final stage = AnchorStage('lib/dup.dart', 'x();')
      ..notUnique('anchor_not_unique')
      ..thenReplace('y();');
    final r = TransformFlow([stage]).evaluate(ctx()).single;
    expect(r, isA<Fail>());
    final diag = (r as Fail).diagnostic;
    expect(diag.code, 'anchor_not_unique');
    expect(diag.message!, contains('matches=2'));
    expect(diag.hint, isNotNull);
    expect(File('${jail.path}/lib/dup.dart').readAsStringSync(), contains('x();'));
  });

  test('missing file guard short-circuits before op emission', () {
    final stage = FileStage('lib/nope.dart')
      ..missing('file_missing')
      ..thenWrite('irrelevant');
    final r = TransformFlow([stage]).evaluate(ctx()).single as Fail;
    expect(r.diagnostic.code, 'file_missing');
  });

  test('when-gate skips its children on false condition', () {
    final gate = WhenStage((ctx) => false, label: 'refactor').then([
      AnchorStage('lib/main.dart', 'runApp();')
        ..notUnique('never_checked'),
    ]);
    final tail = AnchorStage('lib/main.dart', 'runApp();')
      ..notUnique('anchor_not_unique')
      ..thenReplace('runApp(final: true);');
    final report = applyOps(jail.path, TransformFlow([gate, tail]).evaluate(ctx()));
    expect(report.applied, 1);
    expect(File('${jail.path}/lib/main.dart').readAsStringSync(),
        contains('final: true'));
  });

  test('applyOps double-checks uniqueness at apply time (defense in depth)',
      () async {
    const anchor = 'runApp();';
    final stage = AnchorStage('lib/main.dart', anchor)
      ..notUnique('x')
      ..thenReplace('runApp(patched: true);');
    final results = TransformFlow([stage]).evaluate(ctx());
    await Future<void>.delayed(Duration.zero);
    File('${jail.path}/lib/main.dart').writeAsStringSync('$anchor\n$anchor\n');
    final report = applyOps(jail.path, results);
    expect(report.applied, 0);
    expect(report.diagnostics.single.code, 'anchor_not_unique');
  });
}
