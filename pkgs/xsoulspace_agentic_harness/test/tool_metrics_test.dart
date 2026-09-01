// ignore_for_file: lines_longer_than_80_chars

/// Tool-efficiency measurement (ADR 0014/0015). Verifies the measuring
/// wrapper+ledger+analyze cycle captures first-use, in-sequence reuse, cost
/// per call, and failure streaks — and uses it to expose the rename-family
/// redundancy (rename_symbol vs rename_symbol_multi) as a *measured* fact
/// that justifies simplifying the surface.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/observation/tool_metrics.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  late Directory jail;
  late FsToolsRoot root;
  late ToolRegistry base;
  late ToolMetricsLedger ledger;
  late ToolRegistry measured;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('tool_eval_');
    root = FsToolsRoot(jail.path);
    base = ToolRegistry();
    fsTools(root).forEach(base.register);
    ledger = ToolMetricsLedger();
    measured = instrumentRegistry(base, ledger);
  });

  tearDown(() async {
    if (jail.existsSync()) await jail.delete(recursive: true);
  });

  test('records first-use, reuse, and cost for a single tool', () async {
    File('${jail.path}/a.dart').writeAsStringSync('const x = 1;\n');
    await measured.get(const ToolName('read'))!.execute({'path': 'a.dart'});
    await measured.get(const ToolName('read'))!.execute({'path': 'a.dart'});

    expect(ledger.calls, hasLength(2));
    expect(ledger.calls[0].isFirstUse, isTrue);
    expect(ledger.calls[1].isFirstUse, isFalse);
    expect(ledger.calls.every((c) => c.ok), isTrue);
    expect(ledger.calls[0].resultChars, greaterThan(0));

    final report = analyzeTools(ledger);
    final readStat = report.stat('read');
    expect(readStat!.total, 2);
    expect(readStat.firstUseOk, isTrue);
    expect(readStat.avgChars, greaterThan(0));
    expect(readStat.maxFailureStreak, 0);
  });

  test('a failing tool is recorded as a record, never throw-swallowed', () async {
    File('${jail.path}/present.dart').writeAsStringSync('hello');
    // Success first.
    await measured.get(const ToolName('read'))!.execute({'path': 'present.dart'});
    // Then failure: missing file. read throws synchronously? It is sync; the
    // wrapper calls it inside try/catch so it becomes a failure record, and
    // then rethrows as _ToolInstrumentationError.
    await expectLater(
      measured.get(const ToolName('read'))!.execute({'path': 'missing.dart'}),
      throwsA(isA<Exception>()),
    );
    final report = analyzeTools(ledger);
    final readStat = report.stat('read')!;
    expect(readStat.total, 2);
    expect(readStat.okCount, 1);
    expect(readStat.failCount, 1);
    expect(readStat.firstUseOk, isTrue); // first call succeeded
  });

  test('grep reuse is measured — first use + in-sequence reuse cost', () async {
    File('${jail.path}/lib_a.dart').writeAsStringSync('class Widget {}\n');
    // The legacy rename_symbol surface was hard-cut (B4); the discovery
    // sibling `grep` exercises first-use + reuse on the real surface.
    await measured.get(const ToolName('grep'))!.execute({'pattern': 'Widget'});
    await measured.get(const ToolName('grep'))!.execute({'pattern': 'class'});

    final report = analyzeTools(ledger);
    final grep = report.stat('grep');
    expect(grep, isNotNull);
    expect(report.stat('rename_symbol'), isNull); // deleted (B4 hard cut)
    expect(grep!.total, 2);
    expect(grep.firstUseOk, isTrue);
    expect(grep.successRate, 1.0);
  });
}
