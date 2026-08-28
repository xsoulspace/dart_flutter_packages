// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage F3 — meaning-tree growth arm (LLM-free).
///
/// Claim under test: the meaning tree is world state projected per decision,
/// so cost stays FLAT as the tree grows 10× / 100× — the same law as memory
/// beats. The model's cut (`list`) is capped by [maxNodes] and [tokenBudget];
/// the *cut latency* must not scale with tree size beyond graph maintenance.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

World _world() => World()..addPlugin(AgentPlugin());

void _grow(World world, int nodes, {String kind = 'cell'}) {
  final w = world;
  for (var i = 0; i < nodes; i++) {
    addMeaningNode(w, kind: kind, label: '$kind $i');
  }
}

void main() {
  test('cut is budgeted and truthful at 1k / 10k / 100k nodes', () {
    const sizes = [1000, 10000, 100000];
    final latencies = <Duration>[];
    for (final size in sizes) {
      final world = _world();
      _grow(world, size);
      final sw = Stopwatch()..start();
      final cut = meaningCut(
        world,
        query: 'cell 3',
        focusIds: ['cell_2'],
        maxNodes: 64,
        tokenBudget: 2048,
      );
      sw.stop();
      latencies.add(sw.elapsed);
      expect(cut['total'], size); // cut reports true size
      expect((cut['nodes'] as List).length, lessThanOrEqualTo(64));
      // focus + its neighborhood are always in-frame
      final ids = (cut['nodes'] as List).cast<Map>().map((n) => n['id']);
      expect(ids, contains('cell_2'));
      expect(cut['truncated'], size > 64);
    }
    // The cut NEVER serializes more than the budget (flat tokens/decision);
    // selection walks adjacency + a bounded id-map scan, so latency stays
    // small even at 100k nodes. Generous ceiling keeps this LLM-free and
    // CI-stable.
    expect(
      latencies.last.inMilliseconds,
      lessThan(latencies.first.inMilliseconds + 50),
    );
  });

  test('token budget forces a smaller cut before maxNodes does', () {
    final world = _world();
    _grow(world, 200, kind: 'wide');
    final cut = meaningCut(
      world,
      maxNodes: 200,
      tokenBudget: 512,
    );
    expect((cut['nodes'] as List).length, lessThan(200));
    expect(cut['truncated'], true);
  });

  test('neighborhood of focus stays coherent across link hops', () {
    final world = _world();
    _grow(world, 50);
    linkMeaning(world, from: 'cell_1', relation: 'next', to: 'cell_2');
    linkMeaning(world, from: 'cell_2', relation: 'next', to: 'cell_3');
    final cut = meaningCut(world, focusIds: ['cell_2'], maxNodes: 8);
    final ids = (cut['nodes'] as List).cast<Map>().map((n) => n['id']);
    expect(ids, containsAll(['cell_1', 'cell_2', 'cell_3']));
    final edges = (cut['edges'] as List).cast<Map>();
    expect(
      edges.any((e) => e['from'] == 'cell_1' && e['to'] == 'cell_2'),
      isTrue,
    );
  });
}
