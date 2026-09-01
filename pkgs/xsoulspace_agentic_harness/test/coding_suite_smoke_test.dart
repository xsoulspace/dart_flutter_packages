// ignore_for_file: lines_longer_than_80_chars

/// Smoke test for the 20-task coding suite pipeline.
///
/// Runs the full runner against the scripted (no-LLM) handler and asserts
/// every task passes. This proves: YAML parsing, jail seeding, harness loop,
/// tool execution, checker evaluation — the whole path an AFM/pi run will
/// take — without any model.
library;

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/runner.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/scripted_handler.dart';
import 'package:xsoulspace_agentic_harness/src/benchmark/coding_suite/task_spec.dart';

void main() {
  test(
    'scripted run passes all 20 tasks end-to-end',
    () async {
      final tasks = loadTasks('benchmark/coding_suite/tasks');
      expect(
        tasks,
        hasLength(23),
        reason: 'suite must contain exactly 23 tasks',
      );

      final result = await CodingSuiteRunner(
        buildHandler: (task) => ScriptedSuiteHandler(taskId: task.id),
      ).runAll(tasks);

      final failures = [
        for (final r in result.results)
          if (!r.passed)
            '${r.taskId}: ${r.checkerResults.where((c) => !c.passed).map((c) => c.detail)}',
      ];
      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(result.passRate, 1.0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
