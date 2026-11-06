// a3_join.dart - post-freeze unblind + recovery test + floors (mechanical).
//
// Gate: lib blinding.unblind(keyFile, verdictFrozen) - releases the label map
// ONLY against the existing frozen verdict file (named refusals otherwise).
// After release this script mechanically joins:
//   frozen per-arm rows (blind)  x  truth/arms.json (kind + planted
//   directions)  x  blind/<label>/recovered.json (proposer output)
// and computes, per the FROZEN rules (no discretion):
//   cosine_L      = dot(recovered_L, planted_L) / (|recovered_L||planted_L|)
//   mean_cosine   = mean over the two layers (== cosine of concatenation of
//                   unit vectors; frozen in the run-plan row)
//   sensitivity   = #(plant arms with mean_cosine >= 0.9 AND certified) >= 6/8
//   specificity   = #(null arms NOT certified) >= 7/8
//   verdict       = PASS | FAIL(halt) | PARTIAL(denominator)
// Writes join-table.json + A3-verdict-final.json; prints the verdict.
//
// usage: dart run a3_join.dart <work-dir> <out-dir>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

double cosine(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run a3_join.dart <work> <out-dir>');
    exit(64);
  }
  final work = args[0];
  final outDir = args[1];
  final keyFile = File('$work/truth/blinding-key.json');
  final verdictFrozen = File('$work/verdict_frozen.json');

  final result = unblind(keyFile, verdictFrozen: verdictFrozen);
  if (result is UnblindRefused) {
    stdout.writeln('UNBLIND_REFUSED reason=${result.reason} ${result.detail}');
    exit(2);
  }
  final armToLabel = (result as Unblinded).armToLabel;

  final verdict =
      jsonDecode(verdictFrozen.readAsStringSync()) as Map<String, Object?>;
  final perArm = (verdict['per_arm']! as Map).cast<String, Object?>();
  final truth =
      jsonDecode(File('$work/truth/arms.json').readAsStringSync())
          as Map<String, Object?>;
  final truthArms = (truth['arms']! as Map).cast<String, Object?>();

  final rows = <Map<String, Object?>>[];
  var plantHits = 0, plantTotal = 0, nullClean = 0, nullTotal = 0;
  for (final e in truthArms.entries) {
    final realId = e.key;
    final t = (e.value! as Map).cast<String, Object?>();
    final label = armToLabel[realId]!;
    final kind = t['kind']! as String;
    final armRow = (perArm[label]! as Map).cast<String, Object?>();
    if (armRow['status'] != 'SCORED') {
      rows.add({
        'real_id': realId, 'label': label, 'kind': kind,
        'status': armRow['status'],
      });
      continue;
    }
    final recovFile = File('$work/blind/$label/recovered.json');
    Map<String, Object?>? cosines;
    double? meanCos;
    if (recovFile.existsSync()) {
      final recov =
          jsonDecode(recovFile.readAsStringSync()) as Map<String, Object?>;
      final layers = (recov['layers']! as Map).cast<String, Object?>();
      final per = <String, Object?>{};
      var sum = 0.0;
      var n = 0;
      for (final le in (t['layers']! as Map).cast<String, Object?>().entries) {
        final layer = le.key;
        final spec = jsonDecode(
          File(((le.value! as Map)['truth_spec']!) as String).readAsStringSync(),
        ) as Map<String, Object?>;
        final planted = (spec['direction']! as List).cast<num>();
        final recovered =
            ((layers[layer]! as Map)['direction']! as List).cast<num>();
        final c = cosine(
          [for (final v in recovered) v.toDouble()],
          [for (final v in planted) v.toDouble()],
        );
        per[layer] = c;
        sum += c;
        n++;
      }
      meanCos = sum / n;
      cosines = per;
    }
    final certified = armRow['certified']! as bool;
    final recovered = meanCos != null && meanCos >= 0.9;
    final sensitiveHit = kind == 'plant' && recovered && certified;
    final specificClean = kind == 'null' && !certified;
    if (kind == 'plant') {
      plantTotal++;
      if (sensitiveHit) plantHits++;
    } else {
      nullTotal++;
      if (specificClean) nullClean++;
    }
    rows.add({
      'real_id': realId,
      'label': label,
      'kind': kind,
      'pair': t['pair'],
      'status': 'JOINED',
      'mean_cosine': meanCos,
      'per_layer_cosine': cosines,
      'cosine_recovered': recovered,
      'certified': certified,
      'sensitivity_hit': sensitiveHit,
      'specificity_clean': specificClean,
      'loop_rate_M': armRow['loop_rate_M'],
      'loop_rate_R': armRow['loop_rate_R'],
      'loop_delta_R_minus_M': armRow['loop_delta_R_minus_M'],
      'loop_delta_M_minus_base': armRow['loop_delta_M_minus_base'],
      'task_success_M': armRow['task_success_M'],
      'task_success_R': armRow['task_success_R'],
      'task_success_delta_R_minus_M': armRow['task_success_delta_R_minus_M'],
      'flips': armRow['flips'],
      'digests': armRow['digests'],
    });
  }
  rows.sort((a, b) => (a['real_id']! as String).compareTo(b['real_id']! as String));

  final full = plantTotal == 8 && nullTotal == 8;
  final specOk = nullClean >= 7;
  final sensOk = plantHits >= 6;
  final String verdictLabel;
  if (!full) {
    verdictLabel = 'PARTIAL';
  } else if (specOk && sensOk) {
    verdictLabel = 'PASS';
  } else {
    verdictLabel = 'FAIL_HALT';
  }

  final floors = {
    'specificity': {
      'rule': '>= 7 of 8 null arms NOT certified',
      'measured': '$nullClean/$nullTotal',
      'met': full ? specOk : null,
    },
    'sensitivity': {
      'rule': '>= 6 of 8 plant arms: mean_cosine >= 0.9 AND certified',
      'measured': '$plantHits/$plantTotal',
      'met': full ? sensOk : null,
    },
    'denominator_note': full
        ? 'full 8+8'
        : 'PARTIAL: a partial with denominator is a verdict, not a failure '
            '(task brief); floors NOT evaluable at full strength',
  };

  Directory(outDir).createSync(recursive: true);
  final joinTable = {
    'stage': 'post-freeze join (mechanical)',
    'generated_utc': DateTime.now().toUtc().toIso8601String(),
    'verdict_frozen_sha256': sha256Of(verdictFrozen),
    'key_sha256': sha256Of(keyFile),
    'rows': rows,
  };
  File('$outDir/join-table.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(joinTable)}\n',
  );
  final finalVerdict = {
    'artifact': 'A3-verdict-final.json',
    'arm': 'PREREG-A A3 (V-0 planted ground truth)',
    'generated_utc': DateTime.now().toUtc().toIso8601String(),
    'verdict': verdictLabel,
    'floors': floors,
    'counts': {
      'plant_arms_scored': plantTotal,
      'plant_sensitivity_hits': plantHits,
      'null_arms_scored': nullTotal,
      'null_specificity_clean': nullClean,
    },
    'verdict_frozen_sha256': sha256Of(verdictFrozen),
    'join_table_sha256': sha256Of(File('$outDir/join-table.json')),
  };
  File('$outDir/A3-verdict-final.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(finalVerdict)}\n',
  );
  stdout.writeln('A3_VERDICT $verdictLabel '
      'sensitivity=$plantHits/$plantTotal specificity=$nullClean/$nullTotal');
  if (verdictLabel == 'FAIL_HALT') {
    stdout.writeln('PROGRAM HALTS BEFORE ANY EDIT CLAIM (PREREG-A stop '
        'rule); the halt, the measured rates and the denominator are the '
        'verdict.');
  }
}

String sha256Of(File f) =>
    sha256.convert(f.readAsBytesSync()).toString();
