// a3_score.dart - the CERTIFIER stage (blind): battery scoring from the
// frozen cells file. Reads only: cells_frozen_A3.json, base/battery_base.jsonl
// and blind/arm-*/battery_{M,R}.jsonl (+ arm-table.json labels). No truth, no
// key, no kind information is read or written.
//
// Scorers (frozen text in cells_frozen_A3.json 'scorers'):
//   think_prefix_strip, string_first_line, label_first_line (implemented here
//   exactly as frozen), numeric_final + token_limit (via the FROZEN
//   scorers.dart mathScore/tokenLimitRate - run, never edited).
//
// Certification rule (frozen): certified := loop_rate_G2(R) < loop_rate_G2(M)
//   AND task_success(R) >= task_success(M).
//
// usage: dart run a3_score.dart <work-dir> <runs-dir> <out blind-scored.json>
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

// FROZEN think_prefix_strip: if the output (lstrip) starts with the opening
// think tag, drop everything through the first closing think tag inclusive.
// Implemented via split() so no tag literal appears in this source.
String thinkStrip(String o) {
  const openTag = '<think>';
  const closeTag = '</' 'think>';
  if (o.trimLeft().startsWith(openTag)) {
    final parts = o.split(closeTag);
    if (parts.length > 1) {
      return parts.sublist(1).join(closeTag);
    }
  }
  return o;
}

String? firstLine(String o) {
  for (final ln in o.split('\n')) {
    if (ln.trim().isNotEmpty) return ln.trim();
  }
  return null;
}

bool scoreCell(Map<String, Object?> cell, String output) {
  final scorer = cell['scorer']! as String;
  if (scorer == 'numeric_final') {
    return mathScore(thinkStrip(output), cell['gold']! as String) == 1;
  }
  final fl = firstLine(thinkStrip(output));
  if (fl == null) return false;
  final gold = cell['gold']! as String;
  if (scorer == 'label_first_line') return fl.toLowerCase() == gold.toLowerCase();
  if (scorer == 'string_first_line') {
    var s = fl;
    const quotes = '"\'`';
    if (s.length >= 2 && s[0] == s[s.length - 1] && quotes.contains(s[0])) {
      s = s.substring(1, s.length - 1);
    }
    if (!gold.endsWith('.') && s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return s == gold;
  }
  throw StateError('SCORER_UNKNOWN: $scorer');
}

List<Map<String, Object?>> readJsonl(File f) => f
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => (jsonDecode(l) as Map).cast<String, Object?>())
    .toList();

String sha256File(String p) =>
    sha256.convert(File(p).readAsBytesSync()).toString();

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: dart run a3_score.dart <work> <runs> <out.json>');
    exit(64);
  }
  final work = args[0];
  final runs = args[1];
  final cells =
      jsonDecode(File('$runs/cells_frozen_A3.json').readAsStringSync())
          as Map<String, Object?>;
  final groups = (cells['cells']! as Map).cast<String, Object?>();
  final caps =
      ((cells['surface']! as Map)['caps']! as Map).cast<String, Object?>();
  final allCells = <Map<String, Object?>>[
    for (final g in ['G0', 'G1', 'G2', 'pilot'])
      ...(groups[g]! as List).cast<Map<String, Object?>>(),
  ];
  final byId = {for (final c in allCells) c['id']! as String: c};

  Map<String, Object?> scoreRun(File jsonl) {
    final rows = readJsonl(jsonl);
    final perCell = <Map<String, Object?>>[];
    final counts = <String, List<int>>{};
    var taskPass = 0;
    var taskTotal = 0;
    for (final r in rows) {
      final id = r['cell_id']! as String;
      final cell = byId[id]!;
      final group = r['group']! as String;
      final n = r['generated_tokens']! as int;
      (counts[group] ??= <int>[]).add(n);
      final pass = group == 'G2' || group == 'pilot'
          ? null
          : scoreCell(cell, r['output']! as String);
      if (pass != null) {
        taskTotal++;
        if (pass) taskPass++;
      }
      perCell.add({
        'cell_id': id,
        'group': group,
        'generated_tokens': n,
        'cap_hit': r['cap_hit'],
        'pass': pass,
      });
    }
    return {
      'loop_rate_G2': tokenLimitRate(counts['G2']!, caps['G2']! as int),
      'task_success': taskPass / taskTotal,
      'task_pass': taskPass,
      'task_total': taskTotal,
      if (counts.containsKey('pilot'))
        'pilot_loop_rate':
            tokenLimitRate(counts['pilot']!, caps['pilot']! as int),
      'cells': perCell,
      'jsonl_sha256': sha256File(jsonl.path),
    };
  }

  final base = scoreRun(File('$work/base/battery_base.jsonl'));
  final table =
      jsonDecode(File('$work/blind/arm-table.json').readAsStringSync())
          as Map<String, Object?>;
  final labels = [
    for (final a in (table['arms']! as List).cast<Map<String, Object?>>())
      a['label']! as String,
  ]..sort();

  final arms = <String, Object?>{};
  for (final label in labels) {
    final dir = Directory('$work/blind/$label');
    if (!File('${dir.path}/battery_M.jsonl').existsSync() ||
        !File('${dir.path}/battery_R.jsonl').existsSync()) {
      arms[label] = {'status': 'MISSING_BATTERIES'};
      continue;
    }
    final m = scoreRun(File('${dir.path}/battery_M.jsonl'));
    final r = scoreRun(File('${dir.path}/battery_R.jsonl'));
    final loopM = m['loop_rate_G2']! as double;
    final loopR = r['loop_rate_G2']! as double;
    final succM = m['task_success']! as double;
    final succR = r['task_success']! as double;
    final certified = loopR < loopM && succR >= succM;
    final mCells = (m['cells']! as List).cast<Map<String, Object?>>();
    final rCells = (r['cells']! as List).cast<Map<String, Object?>>();
    final flips = <Map<String, Object?>>[];
    for (var i = 0; i < mCells.length; i++) {
      final mc = mCells[i];
      final rc = rCells[i];
      if (mc['cell_id'] != rc['cell_id']) {
        throw StateError('CELL_ORDER_MISMATCH at $i for $label');
      }
      if (mc['pass'] != rc['pass']) {
        flips.add({
          'cell_id': mc['cell_id'],
          'M': mc['pass'],
          'R': rc['pass'],
        });
      }
    }
    String digestOf(String name) {
      final f = File('${dir.path}/$name');
      return f.existsSync() ? sha256File(f.path) : 'MISSING';
    }
    arms[label] = {
      'status': 'SCORED',
      'loop_rate_M': loopM,
      'loop_rate_R': loopR,
      'loop_delta_R_minus_M': loopR - loopM,
      'loop_delta_M_minus_base': loopM - (base['loop_rate_G2']! as double),
      'task_success_M': succM,
      'task_success_R': succR,
      'task_success_delta_R_minus_M': succR - succM,
      'task_pass_M': m['task_pass'],
      'task_pass_R': r['task_pass'],
      'certified': certified,
      'flips': flips,
      'digests': {
        'battery_M': m['jsonl_sha256'],
        'battery_R': r['jsonl_sha256'],
        'recovered_json': digestOf('recovered.json'),
        'mirror_receipt': digestOf('mirror_receipt.json'),
        'repair_receipt': digestOf('repair_receipt.json'),
        'arm_receipt': digestOf('arm_receipt.json'),
      },
    };
  }

  final out = {
    'stage': 'certifier (blind)',
    'generated_utc': DateTime.now().toUtc().toIso8601String(),
    'cells_sha256': sha256File('$runs/cells_frozen_A3.json'),
    'certification_rule': cells['certification_rule_frozen'],
    'base': {
      'loop_rate_G2': base['loop_rate_G2'],
      'task_success': base['task_success'],
      'task_pass': base['task_pass'],
      'task_total': base['task_total'],
      'pilot_loop_rate': base['pilot_loop_rate'],
      'jsonl_sha256': base['jsonl_sha256'],
    },
    'arms': arms,
  };
  File(args[2]).writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(out)}\n',
  );
  stdout.writeln('SCORE_OK ${args[2]} arms=${labels.length}');
}
