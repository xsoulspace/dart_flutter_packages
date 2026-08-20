// ignore_for_file: lines_longer_than_80_chars

/// Phase 0 — tests for the benchmark harness itself.
///
/// Verifies the benchmark measures what it claims: tokens per decision,
/// LLM calls per task, context growth, and the budget invariant.
library;

import 'package:test/test.dart';

import '../benchmark/harness_benchmark.dart';

void main() {
  group('runBenchmark', () {
    test('counts one LLM call per decision', () async {
      final run = await runBenchmark(
        ScriptedTask(name: 't', decisions: ['d1', 'd2', 'd3']),
      );
      expect(run.llmCalls, 3);
      expect(run.success, isTrue);
      expect(run.tokensPerDecision.length, 3);
    });

    test('records context growth across decisions', () async {
      final run = await runBenchmark(
        ScriptedTask(name: 't', decisions: ['d1', 'd2', 'd3']),
      );
      // Context should grow (each response is appended to memory) but stay
      // within the budget.
      expect(run.contextGrowth.length, 3);
      expect(
        run.contextGrowth.last,
        greaterThanOrEqualTo(run.contextGrowth.first),
      );
      expect(run.budgetExceeded, isFalse);
    });

    test('fails when a projection exceeds the token budget', () async {
      final run = await runBenchmark(
        ScriptedTask(
          name: 't',
          decisions: [
            'This is a deliberately long decision prompt that should consume many tokens.',
          ],
          tokenBudget: 1, // absurdly tight — must fail
        ),
      );
      expect(run.budgetExceeded, isTrue);
      expect(run.passed, isFalse);
    });

    test('passes when within budget', () async {
      final run = await runBenchmark(
        ScriptedTask(name: 't', decisions: ['d1']),
      );
      expect(run.passed, isTrue);
    });
  });

  group('BenchmarkReport', () {
    test('summarizes pass/fail and averages', () async {
      final report = await runBenchmarkSuite([
        ScriptedTask(name: 'a', decisions: ['d1']),
        ScriptedTask(
          name: 'b',
          decisions: [
            'This is a deliberately long decision prompt that should consume many tokens.',
          ],
          tokenBudget: 1, // fails
        ),
      ]);
      expect(report.totalRuns, 2);
      expect(report.passedRuns, 1);
      expect(report.failedRuns, 1);
      expect(report.summary, contains('1/2 passed'));
    });
  });
}
