// v3_join.dart - V-3 post-freeze unblind + recovery data + concordance
// criterion (mechanical; PREREG-D addendum 2026-11-06b).
//
// Gate: lib blinding.unblind(keyFile, verdictFrozen) - releases the label map
// ONLY against the existing frozen verdict file (named refusals otherwise).
// After release this script mechanically joins:
//   frozen per-arm rows (blind) x truth/arms.json (kind + planted specs)
//   x blind/<label>/recovered.json (proposer output)
// and computes:
//   cosine_L    = dot(recovered_L, planted_L) / (|recovered_L||planted_L|)
//                 (RECORDED AS DATA; cross-cast cosine is NOT a criterion)
//   criterion   = (# certified plant arms >= 3 of 4) AND
//                 (# NOT-certified null arms == 4 of 4)
//   verdict     = REPLICATION_PASS_ON_SECOND_CAST | REPLICATION_FAIL |
//                 PARTIAL(denominator)
// Writes join-table.json + V3-verdict-final.json; prints the verdict.
//
// usage: dart run v3_join.dart <work-dir> <out-dir>
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
    stderr.writeln('usage: dart run v3_join.dart <work> <out-dir>');
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
  var plantsCertified = 0, plantTotal = 0;
  var nullsClean = 0, nullTotal = 0;
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
    if (kind == 'plant') {
      plantTotal++;
      if (certified) plantsCertified++;
    } else {
      nullTotal++;
      if (!certified) nullsClean++;
    }
    rows.add({
      'real_id': realId,
      'label': label,
      'kind': kind,
      'pair': t['pair'],
      'status': 'JOINED',
      'mean_cosine_data_only': meanCos,
      'per_layer_cosine_data_only': cosines,
      'certified': certified,
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

  final full = plantTotal == 4 && nullTotal == 4;
  final String verdictLabel;
  if (!full) {
    verdictLabel = 'PARTIAL';
  } else if (plantsCertified >= 3 && nullsClean == 4) {
    verdictLabel = 'REPLICATION_PASS_ON_SECOND_CAST';
  } else {
    verdictLabel = 'REPLICATION_FAIL';
  }

  final criterion = {
    'rule_frozen': 'PREREG-D addendum 2026-11-06b: certification concordance '
        '(loop-rate down AND task-success not down on the second cast\'s own '
        'frozen cells) on >= 3/4 plants AND specificity 4/4',
    'plants_certified': {'measured': '$plantsCertified/$plantTotal',
                         'needed': 3},
    'nulls_clean': {'measured': '$nullsClean/$nullTotal', 'needed': 4},
    'cosine_note': 'per-arm cosines recorded as DATA ONLY; cross-cast '
        'direction cosine is NOT a criterion (different weight spaces); '
        'design note: cosine at the FIRST planted layer is ~trivial by '
        'MLP-input-capture causality (the capture point is upstream of that '
        'layer\'s own down_proj edit); the discriminating recovery signal is '
        'the second planted layer\'s cascade cosine + certification',
  };

  Directory(outDir).createSync(recursive: true);
  final joinTable = {
    'stage': 'V-3 post-freeze join (mechanical)',
    'generated_utc': DateTime.now().toUtc().toIso8601String(),
    'verdict_frozen_sha256': sha256Of(verdictFrozen),
    'key_sha256': sha256Of(keyFile),
    'rows': rows,
  };
  File('$outDir/join-table.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(joinTable)}\n',
  );
  final finalVerdict = {
    'artifact': 'V3-verdict-final.json',
    'arm': 'PREREG-D V-3 cross-cast replication (second cast, K=4+4)',
    'generated_utc': DateTime.now().toUtc().toIso8601String(),
    'verdict': verdictLabel,
    'criterion': criterion,
    'counts': {
      'plant_arms_scored': plantTotal,
      'plants_certified': plantsCertified,
      'null_arms_scored': nullTotal,
      'nulls_clean': nullsClean,
    },
    'verdict_frozen_sha256': sha256Of(verdictFrozen),
    'join_table_sha256': sha256Of(File('$outDir/join-table.json')),
  };
  File('$outDir/V3-verdict-final.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(finalVerdict)}\n',
  );
  stdout.writeln('V3_VERDICT $verdictLabel plants_certified='
      '$plantsCertified/$plantTotal nulls_clean=$nullsClean/$nullTotal');
}

String sha256Of(File f) =>
    sha256.convert(f.readAsBytesSync()).toString();
