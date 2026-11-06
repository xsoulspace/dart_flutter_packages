// a3_preflight.dart - frozen-artifact + probe-disjointness preflight.
//
// Runs AFTER the cells/banks freeze and BEFORE any plant run:
//  1. digests the frozen artifacts (cells file, localization banks);
//  2. builds the three probe sets (localization = 256 capture prompts;
//     certification = G0+G1+G2 cell prompts; generalization-slot = the 16
//     pilot cells, held out from both) and runs the FROZEN
//     ProbeBookkeeping.assertDisjoint (overlap = refuse, not warning);
//  3. writes a textual preflight receipt.
//
// usage: dart run a3_preflight.dart <runs-dir> <out-receipt.json>
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

String sha256Text(String s) => sha256.convert(utf8.encode(s)).toString();

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run a3_preflight.dart <runs-dir> <out.json>');
    exit(64);
  }
  final runs = args[0];
  final cellsFile = File('$runs/cells_frozen_A3.json');
  final cells = jsonDecode(cellsFile.readAsStringSync()) as Map<String, Object?>;
  final cellGroups = cells['cells']! as Map<String, Object?>;

  List<String> promptsOf(String path) => File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  final loopPrompts =
      promptsOf('$runs/prompts_localization_loop_A3.txt');
  final neutralPrompts =
      promptsOf('$runs/prompts_localization_neutral_A3.txt');

  List<Map<String, Object?>> group(String g) =>
      (cellGroups[g]! as List).cast<Map<String, Object?>>();

  final certCells = [...group('G0'), ...group('G1'), ...group('G2')];
  final pilotCells = group('pilot');

  final set = ProbeSet(
    localization: [
      for (final p in [...loopPrompts, ...neutralPrompts]) sha256Text(p),
    ],
    certification: [
      for (final c in certCells) sha256Text(c['prompt']! as String),
    ],
    generalization: [
      for (final c in pilotCells) sha256Text(c['prompt']! as String),
    ],
  );
  // G-cell name vocabulary (probes.dart CellRef - names are the contract)
  final cellRefs = [
    const CellRef('G0-slugify'),
    const CellRef('G1-perm'),
    const CellRef('G2-loop-rate'),
    const CellRef('pilot-loop-rate'),
  ];
  try {
    ProbeBookkeeping.assertDisjoint(set);
  } on ProbeSetViolation catch (e) {
    stdout.writeln('PREFLIGHT_REFUSED $e');
    exit(1);
  }

  final receipt = {
    'tool': 'a3_preflight.dart',
    'at': DateTime.now().toUtc().toIso8601String(),
    'verdict': 'PREFLIGHT_OK',
    'cell_refs': [for (final r in cellRefs) r.name],
    'frozen_artifacts': {
      'cells_frozen_A3.json': sha256.convert(cellsFile.readAsBytesSync()).toString(),
      'prompts_localization_loop_A3.txt': sha256.convert(
        File('$runs/prompts_localization_loop_A3.txt').readAsBytesSync(),
      ).toString(),
      'prompts_localization_neutral_A3.txt': sha256.convert(
        File('$runs/prompts_localization_neutral_A3.txt').readAsBytesSync(),
      ).toString(),
    },
    'probe_sets': {
      'localization': set.localization.length,
      'certification': set.certification.length,
      'generalization_slot_pilot': set.generalization.length,
      'disjoint': true,
    },
  };
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(receipt)}\n',
  );
  stdout.writeln('PREFLIGHT_OK ${args[1]}');
}
