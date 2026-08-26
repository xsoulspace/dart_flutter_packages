// ignore_for_file: lines_longer_than_80_chars

/// End-to-end proof (M2+M4 on a real suite task family):
/// baseline whole-file arm vs ops arm (`patch_file` + `verify_pack`
/// registered), measured through the M1 attribution ledger.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/ops_handler.dart'
    show OpsSuiteHandler, WholeFileSuiteHandler;

const _tasksDir = 'benchmark/coding_suite/tasks_ops';

Future<({SuiteResult result, AttributionLedger ledger})> _runArm({
  required bool ops,
}) async {
  final tasks = loadTasks(_tasksDir);
  expect(tasks, hasLength(1));
  final task = tasks.single;

  final ledger = AttributionLedger();
  GenerationHandler handler(CodingTask t) => AttributedHandler(
        ops
            ? OpsSuiteHandler(taskId: t.id)
            : WholeFileSuiteHandler(taskId: t.id),
        ledger,
      );

  final runner = CodingSuiteRunner(
    buildHandler: handler,
    backendLabel: ops ? 'ops' : 'baseline',
    modelLabel: 'scripted',
    extraTools: [patchFileTool],
  );
  final result = await runner.runAll([task]);
  return (result: result, ledger: ledger);
}

void main() {
  test('ops arm passes the family with fewer generated chars than baseline',
      () async {
    final base = await _runArm(ops: false);
    expect(base.result.passRate, 1);

    final ops = await _runArm(ops: true);
    expect(ops.result.passRate, 1);

    final baseGen = base.ledger.summarize()['generatedChars'] as int;
    final opsGen = ops.ledger.summarize()['generatedChars'] as int;
    expect(baseGen, greaterThan(opsGen));
    final cut = 1 - opsGen / baseGen;
    expect(cut, greaterThanOrEqualTo(0.30),
        reason: 'baseline=$baseGen ops=$opsGen');

    // One patch call + one close-out — same decision count as baseline
    // (fair comparison); only the payload size differs.
    final opsRow = ops.result.results.single;
    expect(opsRow.passed, isTrue);
    expect(opsRow.llmCalls, base.result.results.single.llmCalls);
  });

  test('patch_file rejects ambiguous anchors with structured diagnostics',
      () async {
    final jail = await Directory.systemTemp.createTemp('patch-tool-test');
    addTearDown(() => jail.delete(recursive: true));
    File('${jail.path}/dup.txt').writeAsStringSync('a\na\n');

    final tool = patchFileTool(jail.path);
    final out = await tool.execute({
      'path': 'dup.txt',
      'anchor': 'a',
      'new_text': 'b',
    });
    final map =
        (out is String ? jsonDecode(out) : out) as Map<String, dynamic>;
    expect(map['ok'], false);
    expect(map['code'], 'anchor_not_unique');
    expect(map['matches'], 2);
    expect(map['hint'] as String, contains('exactly once'));
    expect(File('${jail.path}/dup.txt').readAsStringSync(), 'a\na\n');
  });
}
