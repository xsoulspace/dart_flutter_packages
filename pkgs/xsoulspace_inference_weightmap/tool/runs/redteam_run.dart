/// V-4 scorer-tier bench runner (PREREG-C §V-4).
///
/// Reads the planted fake-win fixture, runs the RedTeamBench guards (frozen
/// scorers/probes only), and writes the receipt jsonl: one line per plant
/// {id, class, naive, invariant, length_norm, memo_flag, verdict} plus the
/// summary line {refusals, leaks, floor_met}.
///
/// Run from the package directory:
///   dart run tool/runs/redteam_run.dart [plants.json] [receipt.jsonl]
///
/// Exit code 0 when the frozen 12/12 floor is met, 1 otherwise. The receipt
/// records the TRUTH either way — plants are never tuned to pass (PREREG-C:
/// below floor = scorer-freeze defect, re-freeze via a new prereg row).
library;

import 'dart:io';

import 'package:xsoulspace_inference_weightmap/src/redteam.dart';

void main(List<String> args) {
  final plantsPath =
      args.isNotEmpty ? args[0] : 'tool/runs/redteam_plants.json';
  final receiptPath =
      args.length > 1 ? args[1] : 'receipts/V4-scorer-tier.jsonl';

  final bench = RedTeamBench.parse(File(plantsPath).readAsStringSync());
  final results = bench.run();
  final summary = bench.summarize(results);
  final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);

  File(receiptPath).writeAsStringSync(
    '${bench.receiptLines(results, date: date).join('\n')}\n',
  );

  stdout.writeln(
    'V-4 scorer tier: refusals=${summary.refusals}/${summary.plantsEvaluated} '
    'leaks=${summary.leaks} floor_met=${summary.floorMet} '
    '(prereg floor ${RedTeamBench.preregRefusalFloor}/'
    '${RedTeamBench.preregRefusalFloor})',
  );
  for (final r in results) {
    stdout.writeln(
      '${r.plant.id} ${r.plant.klass.wire}/${r.plant.subclass} '
      'naive=${r.naiveScore} invariant=${r.invariantScore} '
      'frozen_invariant=${r.frozenInvariantScore} '
      'length_norm=${r.lengthNorm} memo=${r.memoFlag} -> ${r.verdict}'
      '${r.refusal == null ? '' : ' :: ${r.refusal}'}',
    );
  }
  stdout.writeln('receipt: $receiptPath');
  if (!summary.floorMet) exitCode = 1;
}
