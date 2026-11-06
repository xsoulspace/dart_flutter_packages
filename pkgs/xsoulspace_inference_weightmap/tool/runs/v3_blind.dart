// v3_blind.dart - V-3 blinding setup (orchestrator-only, runs ONCE pre-arm).
//
// V-3 seed law (task brief 2026-11-06, recorded pre-run): blinding seed
// "20261106-V3" = BlindingPlan.fromSeed(20261106, arms v3-plant-1..4 +
// v3-null-1..4). The 20261105 seed belongs to A3's sealed plan (used in V-3
// ONLY for the frozen pair_columns procedure per the task pin); the new
// (seed, arms) pair is distinct from A3's.
// Writes:
//   <work>/truth/blinding-key.json  (sealed key; lib unblind() gate consumes)
//   <work>/truth/labelmap.json      (orchestrator-only: real->label, used by
//                                    v3_truth.py for blind spec placement)
// usage: dart run v3_blind.dart <work-dir>
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run v3_blind.dart <work-dir>');
    exit(64);
  }
  const seed = 20261106; // V-3 blinding seed ("20261106-V3", recorded pre-run)
  final arms = <String>[
    for (var k = 1; k <= 4; k++) 'v3-plant-$k',
    for (var k = 1; k <= 4; k++) 'v3-null-$k',
  ];
  final plan = BlindingPlan.fromSeed(seed, arms);
  final work = args[0];
  final keyFile = File('$work/truth/blinding-key.json');
  plan.writeKeyFile(keyFile);
  File('$work/truth/labelmap.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(plan.armToLabel)}\n',
  );
  stdout.writeln('BLIND_OK seed=$seed arms=${arms.length} key=${keyFile.path}');
  stdout.writeln(canonicalJson(plan.armToLabel));
}
