/// Phase 0 — runnable benchmark entrypoint.
///
/// Usage:
///   dart run benchmark/run_benchmark.dart
///
/// Prints a summary report and exits non-zero if any run failed its budget.
library;

import 'dart:io';

import 'harness_benchmark.dart';

Future<void> main() async {
  final report = await runBenchmarkSuite([
    ScriptedTask(
      name: 'single-decision',
      decisions: ['Reply with one word: hello.'],
    ),
    ScriptedTask(
      name: 'multi-decision',
      decisions: [
        'First step: say ready.',
        'Second step: confirm done.',
        'Third step: finish.',
      ],
    ),
    ScriptedTask(
      name: 'tight-budget-1k',
      decisions: ['Reply with one word: hello.'],
      tokenBudget: 1000,
    ),
  ]);

  stdout.writeln(report.summary);

  if (report.failedRuns > 0) {
    exitCode = 1;
  }
}
