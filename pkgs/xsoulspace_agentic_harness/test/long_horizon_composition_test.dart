// ignore_for_file: lines_longer_than_80_chars

/// R2 (ADR 0020) — flat tokens/decision must SURVIVE the cut composition.
/// The legacy gate (`long_horizon_test.dart`) proves the ranked cut; this
/// gate proves the composed cut (working set + map absence + observations
/// slot) holds the same scaling property as the graph grows 300 beats.
library;

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/long_horizon_benchmark.dart';

void main() {
  test(
    'R2: composed cut — tokens/decision stay flat over 300 decisions',
    () async {
      final result = await runLongHorizonBenchmark(
        decisions: 300,
        withComposition: true,
      );
      expect(result.totalBeats, greaterThanOrEqualTo(300));
      expect(
        result.flatnessRatio,
        lessThan(1.40),
        reason:
            'composed-cut tokens/decision drifted upward: '
            'early=${result.earlyAvgTokens} late=${result.lateAvgTokens}',
      );
      expect(result.budgetExceeded, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
