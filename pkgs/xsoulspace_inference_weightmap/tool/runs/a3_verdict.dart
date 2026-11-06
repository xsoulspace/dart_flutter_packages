// a3_verdict.dart - FREEZE the blind verdict artifact (pre-unblind).
//
// Assembles verdict_frozen.json from the blind-scored table: per-arm blinded
// rows (label, certified, loop/task metrics, recovered-direction digests),
// the frozen floor text, the certification rule, artifact digests, and the
// achieved denominator. Nothing in this file reads the key or truth. The
// sha256 of the written file is printed - that digest is the freeze handle
// the unblind gate is released against (lib blinding.unblind requires this
// file to exist; its CONTENT is label-blind by construction).
//
// usage: dart run a3_verdict.dart <work-dir> <runs-dir>
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run a3_verdict.dart <work> <runs>');
    exit(64);
  }
  final work = args[0];
  final runs = args[1];
  final scored =
      jsonDecode(File('$work/blind-scored.json').readAsStringSync())
          as Map<String, Object?>;
  final cells =
      jsonDecode(File('$runs/cells_frozen_A3.json').readAsStringSync())
          as Map<String, Object?>;
  final arms = (scored['arms']! as Map).cast<String, Object?>();

  final perArm = <String, Object?>{};
  var scoredCount = 0;
  for (final e in arms.entries) {
    final a = (e.value! as Map).cast<String, Object?>();
    if (a['status'] != 'SCORED') {
      perArm[e.key] = {'status': a['status']};
      continue;
    }
    scoredCount++;
    perArm[e.key] = {
      'status': 'SCORED',
      'certified': a['certified'],
      'loop_rate_M': a['loop_rate_M'],
      'loop_rate_R': a['loop_rate_R'],
      'loop_delta_R_minus_M': a['loop_delta_R_minus_M'],
      'loop_delta_M_minus_base': a['loop_delta_M_minus_base'],
      'task_success_M': a['task_success_M'],
      'task_success_R': a['task_success_R'],
      'task_success_delta_R_minus_M': a['task_success_delta_R_minus_M'],
      'flips': a['flips'],
      'digests': a['digests'],
    };
  }

  final verdict = {
    'artifact': 'verdict_frozen.json',
    'law': 'FROZEN pre-unblind (PREREG-A: unblind only after the verdict '
        'file is frozen). Per-arm rows are label-blind; kind/cosine join '
        'happens ONLY after this file exists (a3_join.dart via lib gate).',
    'frozen_utc': DateTime.now().toUtc().toIso8601String(),
    'prereg': {
      'file': '$runs/../../PREREG-A.md',
      'seed': 20261105,
      'floors': cells['floors_frozen'],
      'certification_rule': cells['certification_rule_frozen'],
      'cells_sha256': scored['cells_sha256'],
    },
    'base': scored['base'],
    'denominator': {'expected_arms': 16, 'scored_arms': scoredCount},
    'per_arm': perArm,
  };
  final outPath = '$work/verdict_frozen.json';
  final encoded =
      '${const JsonEncoder.withIndent(' ').convert(verdict)}\n';
  File(outPath).writeAsStringSync(encoded);
  final digest = sha256.convert(File(outPath).readAsBytesSync()).toString();
  stdout.writeln('VERDICT_FROZEN $outPath');
  stdout.writeln('sha256 $digest');
  stdout.writeln('scored_arms $scoredCount/16');
}
