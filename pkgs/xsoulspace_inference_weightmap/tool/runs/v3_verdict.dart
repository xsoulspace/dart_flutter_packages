// v3_verdict.dart - FREEZE the V-3 blind verdict artifact (pre-unblind).
//
// Twin of the A3 freeze tool with the V-3 denominator (8 arms) and the
// PREREG-D addendum 2026-11-06b criterion text. Assembles verdict_frozen.json
// from the blind-scored table: per-arm blinded rows (label, certified,
// loop/task metrics), the frozen criterion text, the certification rule,
// artifact digests, and the achieved denominator. Nothing here reads the key
// or truth. The sha256 of the written file is the freeze handle the unblind
// gate is released against (lib blinding.unblind requires this file to exist;
// its CONTENT is label-blind by construction).
//
// usage: dart run v3_verdict.dart <work-dir> <runs-dir>
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run v3_verdict.dart <work> <runs>');
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
    'artifact': 'verdict_frozen.json (V-3 cross-cast replication)',
    'law': 'FROZEN pre-unblind (unblind only after the verdict file is '
        'frozen; lib blinding.unblind gate). Per-arm rows are label-blind; '
        'kind/cosine join happens ONLY after this file exists (v3_join.dart).',
    'frozen_utc': DateTime.now().toUtc().toIso8601String(),
    'prereg': {
      'file': '$runs/../../PREREG-D.md',
      'addendum': '2026-11-06b (V-3 numeric pins, frozen pre-run)',
      'blinding_seed_label': '20261106-V3',
      'criterion_frozen':
          'certification concordance (loop-rate down AND task-success not '
          'down on the second cast\'s own frozen cells) on >= 3/4 plants '
          'AND specificity 4/4 nulls NOT certified => REPLICATION PASS on '
          'second cast; else FAIL with per-arm rows. Direction cosine '
          'across casts is NOT a criterion (different weight spaces); '
          'within-cast cosines are recorded as data.',
      'certification_rule': cells['certification_rule_frozen'],
      'cells_sha256': scored['cells_sha256'],
    },
    'base': scored['base'],
    'denominator': {'expected_arms': 8, 'scored_arms': scoredCount},
    'per_arm': perArm,
  };
  final outPath = '$work/verdict_frozen.json';
  final encoded =
      '${const JsonEncoder.withIndent(' ').convert(verdict)}\n';
  File(outPath).writeAsStringSync(encoded);
  final digest = sha256.convert(File(outPath).readAsBytesSync()).toString();
  stdout.writeln('VERDICT_FROZEN $outPath');
  stdout.writeln('sha256 $digest');
  stdout.writeln('scored_arms $scoredCount/8');
}
