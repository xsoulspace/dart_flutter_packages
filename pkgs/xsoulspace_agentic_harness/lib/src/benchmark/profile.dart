// ignore_for_file: lines_longer_than_80_chars

/// Profile runner (M1): runs suite [tasks] through the real loop with an
/// [AttributedHandler] wrapper and returns the ranked attribution report.
///
/// Provider-agnostic: pass any [GenerationHandler] factory (scripted,
/// OpenRouter, AFM FFI). The scripted path is LLM-free and finishes in
/// milliseconds, which keeps the feedback loop fast by construction.
library;


import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import '../events.dart';
import '../tooling/attribution.dart';
import 'coding_suite/runner.dart';
import 'coding_suite/task_spec.dart';

Future<String> runProfile(
  List<CodingTask> tasks, {
  required GenerationHandler Function(CodingTask task) buildHandler,
  int maxCheckerRetries = 2,
  List<ToolDef Function(String jailRoot)> extraTools = const [],
  String? tracePath,
}) async {
  final ledger = AttributionLedger();
  GenerationHandler attributed(CodingTask task) =>
      AttributedHandler(buildHandler(task), ledger);

  final runner = CodingSuiteRunner(
    buildHandler: attributed,
    maxCheckerRetries: maxCheckerRetries,
    backendLabel: 'profile',
    modelLabel: 'attributed',
    extraTools: extraTools,
  );
  final sw = Stopwatch()..start();
  final result = await runner.runAll(tasks, tracePath: tracePath);
  sw.stop();

  final buf = StringBuffer()
    ..writeln(result.toMarkdown(label: 'profile'))
    ..write('\n')
    ..write(
      result.results
          .map(
            (r) => r.passed
                ? ''
                : 'FAIL ${r.taskId} mode=${r.failureMode}\n${r.checkerResults
                        .where((c) => !c.passed)
                        .map((c) => '  ✗ ${c.detail}')
                        .join('\n')}',
          )
          .where((t) => t.isNotEmpty)
          .join('\n'),
    )
    ..write('\n')
    ..writeln('total wall: ${sw.elapsedMilliseconds} ms')
    ..write(ledger.report());
  return buf.toString();
}
