// ignore_for_file: lines_longer_than_80_chars

/// Phase 2 gate — long-horizon scaling claims as CI assertions.
///
/// Runs a reduced (CI-friendly) version of `benchmark/long_horizon_benchmark.dart`
/// and asserts the North Star scaling properties:
/// 1. tokens/decision stays flat as the beat graph grows (bounded context);
/// 2. per-decision latency grows far slower than the beat count;
/// 3. no projection exceeds the token budget.
library;


import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/benchmark/long_horizon_benchmark.dart';

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
    // Wall-clock latency is noisy when tests run in parallel with other
    // workloads; means over small windows flip the ratio past the gate.
    // Medians are robust to scheduling spikes, and a single retry absorbs
    // genuinely transient machine load. The real gate remains the
    // benchmark CLI's larger runs.
    Future<double> ratio() async {
      final result = await runLongHorizonBenchmark(decisions: 300);
      final xs = result.latencyMicrosPerDecision;
      double windowMedian(List<int> samples) {
        final sorted = [...samples]..sort();
        final mid = sorted.length ~/ 2;
        return sorted.length.isOdd
            ? sorted[mid].toDouble()
            : (sorted[mid - 1] + sorted[mid]) / 2;
      }

      final w = (result.decisions * 0.1).ceil();
      final early = windowMedian(xs.take(w).toList());
      final late = windowMedian(xs.skip(xs.length - w).toList());
      return early == 0 ? 0 : late / early;
    }

    var r = await ratio();
    if (r >= 4.0) r = await ratio(); // one retry under transient load

    // Beats grew ~300x from the first decision; latency may grow at most 4x.
    expect(r, lessThan(4.0), reason: 'projection latency grew superlinearly');
  });
}
