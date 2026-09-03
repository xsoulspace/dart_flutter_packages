// ignore_for_file: lines_longer_than_80_chars

/// TIER 2 — the WHOLE repository (every package under pkgs/), deterministically
/// ETL'd in and out. At repo scale (≈10.6k symbols / ≈67k edges) the boundedness
/// claims must still hold: fidelity 100%, cuts ≤ budget and FLAT vs tier 1,
/// snapshot/restore complete, decomposition hard-bounded.
///
/// This test is the scale verdict on the North Star mechanics: the meaning
/// tree, ray-cast projection, and planning work WITHOUT a model at a scale
/// a small model could never read raw.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

Directory? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('workspace:')) {
      return dir;
    }
    dir = dir.parent;
  }
  return null;
}

World _world() => World()..addPlugin(AgentPlugin());

void main() {
  test(
    'TIER 2: the whole repo ETLs in, holds (fidelity 100%), and projects '
    'within budget — flat vs tier 1',
    () async {
      final repoRoot = _repoRoot();
      expect(repoRoot, isNotNull);
      final sw = Stopwatch()..start();
      final scans = scanTree(repoRoot!);
      final scanMs = sw.elapsedMilliseconds;

      var files = 0;
      var symbols = 0;
      for (final s in scans.values) {
        files += s.length;
        for (final f in s) {
          symbols += f.symbols.length;
        }
      }
      // Real scale gate: the probe is meaningless on a toy corpus.
      expect(files, greaterThan(500), reason: 'repo lib/test file count');
      expect(symbols, greaterThan(5000), reason: 'repo symbol count');

      final world = _world();
      final built = buildMeaningTreeFromCode(world, scans);
      final buildMs = sw.elapsedMilliseconds - scanMs;
      expect(built.symbols, symbols);

      // 1. ETL-out fidelity: the tree HOLDS the repo structure.
      final fid = fidelityCheck(world, scans);
      expect(
        fid.mismatches,
        0,
        reason:
            'fidelity ${fid.checked - fid.mismatches}/${fid.checked} at repo '
            'scale; samples: ${fid.samples.take(5).join(' | ')}',
      );

      // 2. Cuts bounded AND flat vs tier 1 (the ray-cast claim at 4.5×
      // scale). HarnessLoop is a real, heavily-referenced target.
      final index = world.getResource<MeaningIndex>();
      final target = index.byId.keys
          .where((id) => id.endsWith('_HarnessLoop'))
          .first;
      final cutTokens = <String, int>{};
      for (final zoom in const ['point', 'local', 'region', 'summary']) {
        final cs = Stopwatch()..start();
        final cut = meaningCut(world, focusIds: [target], zoom: zoom);
        cutTokens[zoom] = (cut.toString().length / 4).ceil();
        expect(
          cutTokens[zoom],
          lessThanOrEqualTo(2100),
          reason: 'zoom $zoom rendered ${cutTokens[zoom]} tokens at '
              '${index.nodeCount}-node repo scale',
        );
        expect(
          cs.elapsedMilliseconds,
          lessThan(2000),
          reason: 'zoom $zoom took ${cs.elapsedMilliseconds}ms — projection '
              'latency does not scale with the tree',
        );
      }
      // Flatness: the cut size must not grow with the tree. Tier 1 measured
      // the same target at ~2.3k nodes; tier 2 is ~11.5k — identical budget.
      expect(cutTokens['local'], lessThanOrEqualTo(2100));
      expect(cutTokens['summary'], lessThanOrEqualTo(200));

      // 3. Decomposition hard-bounded at repo scale.
      final frontier = impactFrontier(world, target, maxDepth: 2, maxNodes: 64);
      expect(frontier.length, lessThanOrEqualTo(64));

      // 4. Snapshot carries NO code tree — it re-derives (ADR 0023 §2).
      // This is the fix for the 18s super-linear restore finding: NOT
      // restoring trees. Measure the re-derivation instead.
      final store = SnapshotStore();
      await store.open(
        '${Directory.systemTemp.path}/etl_t2_${DateTime.now().millisecondsSinceEpoch}/store',
      );
      await store.save(world, name: 't2', meta: {'tier': 2});
      final restored = await store.load('t2');
      final rIndex = restored.getResource<MeaningIndex>();
      expect(rIndex.nodeCount, 0,
          reason: 'the tree is re-derived, never restored (ADR 0023 §2)');
      final rederiveSw = Stopwatch()..start();
      buildMeaningTreeFromCode(restored, scans);
      rederiveSw.stop();
      expect(rIndex.nodeCount, index.nodeCount);
      expect(rIndex.edgeCount, index.edgeCount);
      // Re-derived tree is queryable, not just counted.
      final cutAfterRestore = meaningCut(
        restored,
        focusIds: [target],
        zoom: 'local',
      );
      expect(
        (cutAfterRestore.toString().length / 4).ceil(),
        lessThanOrEqualTo(2100),
      );

      // Print the honest measurement row (every number states its source).
      // ignore: avoid_print
      print(
        'TIER2 row — files: $files | symbols: $symbols | edges: '
        '${built.edges} | scan: ${scanMs}ms | build: ${buildMs}ms | '
        'fidelity: ${fid.checked}/${fid.checked} | cuts(tokens): '
        '$cutTokens | re-derivation: ${rIndex.nodeCount}/'
        '${rIndex.edgeCount} in ${rederiveSw.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
