// a3_blind.dart - A3 blinding setup (orchestrator-only, runs ONCE pre-arm).
//
// Frozen law: seed 20261105 (PREREG-A), 16 real arm ids in registration
// order [a3-plant-1..8, a3-null-1..8] -> opaque labels via lib blinding.
// Writes:
//   <work>/truth/blinding-key.json  (the sealed key; unblind() gate consumes)
//   <work>/truth/labelmap.json      (orchestrator-only: real->label, used by
//                                    a3_truth.py for blind spec placement)
// Prints the label map JSON to stdout (setup log; consumed once).
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run a3_blind.dart <work-dir>');
    exit(64);
  }
  const seed = 20261105; // FROZEN (PREREG-A blinding seed)
  final arms = <String>[
    for (var k = 1; k <= 8; k++) 'a3-plant-$k',
    for (var k = 1; k <= 8; k++) 'a3-null-$k',
  ];
  final plan = BlindingPlan.fromSeed(seed, arms);
  final work = args[0];
  final keyFile = File('$work/truth/blinding-key.json');
  plan.writeKeyFile(keyFile);
  File('$work/truth/labelmap.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(plan.armToLabel)}\n',
  );
  stdout.writeln('BLIND_OK seed=$seed key=${keyFile.path}');
  stdout.writeln(canonicalJson(plan.armToLabel));
}
