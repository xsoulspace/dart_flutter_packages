// ignore_for_file: lines_longer_than_80_chars

/// Repository-scale ETL probe (tier 1 + tier 2) — LLM-free measurement of
/// the whole pipeline: scan → meaning tree → cuts → decomposition → plan
/// projection → fidelity. Re-run:
/// `dart run tool/etl_scale_probe.dart [tier1|tier2]`
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

Future<void> main(List<String> args) async {
  final tier = args.isEmpty ? 'tier2' : args.first;
  final repoRoot = Directory.current.parent.parent;
  final root = tier == 'tier1'
      ? Directory('${repoRoot.path}/pkgs/xsoulspace_agentic_harness')
      : Directory('${repoRoot.path}/pkgs');
  final sw = Stopwatch()..start();
  final scans = <String, List<CodeFileScan>>{};
  if (tier == 'tier1') {
    final files = dartFiles(root);
    scans['xsoulspace_agentic_harness'] = [
      for (final f in files)
        scanDartFile(f, f.path.substring(repoRoot.path.length + 1)),
    ];
  } else {
    scans.addAll(scanTree(repoRoot));
  }
  final scanMs = sw.elapsedMilliseconds;
  final totalFiles = scans.values.fold(0, (a, s) => a + s.length);
  var totalSymbols = 0;
  for (final s in scans.values) {
    for (final f in s) {
      totalSymbols += f.symbols.length;
    }
  }
  stdout.writeln(
    'scan: $totalFiles files, $totalSymbols symbols in ${scanMs}ms',
  );

  // Build the tree.
  final world = World()..addPlugin(AgentPlugin());
  final built = buildMeaningTreeFromCode(world, scans);
  final buildMs = sw.elapsedMilliseconds - scanMs;
  stdout.writeln(
    'tree: ${built.files} file nodes, ${built.symbols} symbol nodes, '
    '${built.edges} edges in ${buildMs}ms',
  );

  // Fidelity round-trip.
  final fid = fidelityCheck(world, scans);
  stdout.writeln(
    'fidelity: ${fid.checked - fid.mismatches}/${fid.checked} '
    '(${fid.mismatches} mismatches)${fid.samples.isEmpty ? "" : "\n  e.g. ${fid.samples.take(3).join(" | ")}"}',
  );

  // Bounded cuts at scale: point/local/region/summary around a real symbol
  // (dynamically picked: the HarnessLoop class or any large class).
  final index = world.getResource<MeaningIndex>();
  String? target = index.byId.keys
      .where((id) => id.endsWith('_HarnessLoop'))
      .firstOrNull;
  target ??= index.byId.keys.firstWhere(
    (id) => id.startsWith('sym_') && index.nodeCount > 0,
    orElse: () => index.byId.keys.first,
  );
  stdout.writeln(
    'target: $target (present: ${index.byId.containsKey(target)})',
  );
  for (final zoom in const ['point', 'local', 'region', 'summary']) {
    final cs = Stopwatch()..start();
    final cut = meaningCut(
      world,
      focusIds: [target],
      zoom: zoom,
      tokenBudget: 2048,
    );
    final ms = cs.elapsedMilliseconds;
    final json = cut.toString();
    final tokens = (json.length / 4).ceil();
    final nodes = jsonDecodeList(cut['nodes']);
    final kinds = jsonDecodeList(cut['kinds']);
    stdout.writeln(
      'cut[$zoom]: ~$tokens tokens, ${nodes.whenEmptyUse(kinds).length} entries, ${ms}ms',
    );
  }

  // Impact decomposition (reverse refs).
  final frontier = impactFrontier(world, target, maxDepth: 2, maxNodes: 64);
  stdout.writeln('impact frontier (depth 2): ${frontier.length} nodes');

  // Snapshot/restore equivalence at scale.
  final store = SnapshotStore();
  await store.open(
    '${Directory.systemTemp.path}/etl_probe_${DateTime.now().millisecondsSinceEpoch}/store',
  );
  final sw2 = Stopwatch()..start();
  await store.save(world, name: 'scale', meta: {'tier': tier});
  final saveMs = sw2.elapsedMilliseconds;
  final sw3 = Stopwatch()..start();
  final restored2 = await store.load('scale');
  final restoredIndex = restored2.getResource<MeaningIndex>();
  final restoreMs = sw3.elapsedMilliseconds;
  stdout.writeln(
    'snapshot: save ${saveMs}ms, restore ${restoreMs}ms — nodes '
    '${restoredIndex.nodeCount}/${index.nodeCount}, edges '
    '${restoredIndex.edgeCount}/${index.edgeCount}',
  );
}
