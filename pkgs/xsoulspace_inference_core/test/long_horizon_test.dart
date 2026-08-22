// ignore_for_file: lines_longer_than_80_chars

/// Phase 2 gate — long-horizon scaling claims as CI assertions.
///
/// Runs a reduced (CI-friendly) version of `benchmark/long_horizon_benchmark.dart`
/// and asserts the North Star scaling properties:
/// 1. tokens/decision stays flat as the beat graph grows (bounded context);
/// 2. per-decision latency grows far slower than the beat count;
/// 3. no projection exceeds the token budget.

import 'package:test/test.dart';

import '../benchmark/long_horizon_benchmark.dart';

void main() {
  test(
    'long-horizon: tokens/decision stay flat over 300 decisions',
    () async {
      final result = await runLongHorizonBenchmark(decisions: 300);

      // The graph grew 300 beats; the cut must not grow with it.
      expect(result.totalBeats, greaterThanOrEqualTo(300));
      expect(
        result.flatnessRatio,
        lessThan(1.40),
        reason:
            'tokens/decision drifted upward: '
            'early=${result.earlyAvgTokens} late=${result.lateAvgTokens}',
      );
      expect(result.budgetExceeded, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('long-horizon: projection latency stays sublinear', () async {
    final result = await runLongHorizonBenchmark(decisions: 300);

    // Beats grew ~300x from the first decision; latency may grow at most 4x.
    // (JIT warm-up makes early windows artificially fast, so this is loose —
    // the real gate is the benchmark CLI's larger runs.)
    expect(
      result.latencyGrowthRatio,
      lessThan(4.0),
      reason:
          'projection latency grew superlinearly: '
          'early=${result.earlyAvgLatency}µs late=${result.lateAvgLatency}µs',
    );
  });
}
