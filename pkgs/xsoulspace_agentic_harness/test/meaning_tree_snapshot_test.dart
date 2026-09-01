// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage F4 — meaning-tree snapshot parity (LLM-free).
///
/// The tree's truth is world components (nodes/edges/props); the meaning
/// index and facet keywords are derived. Round-trip must restore component
/// truth (via persistent ids for edge refs) and re-derive the indices so a
/// cut after restore equals the cut before.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

World _built() {
  final world = World()..addPlugin(AgentPlugin());
  addMeaningNode(world, kind: 'board', label: 'tictactoe', props: {'size': 3});
  addMeaningNode(world, kind: 'cell', label: 'top-left');
  addMeaningNode(world, kind: 'cell', label: 'top-right');
  linkMeaning(world, from: 'board_1', relation: 'contains', to: 'cell_1');
  linkMeaning(world, from: 'board_1', relation: 'contains', to: 'cell_2');
  setMeaningProp(world, id: 'cell_1', key: 'marker', value: 'X');
  return world;
}

void main() {
  test('snapshot → restore keeps the tree; cut output is identical', () {
    final before = _built();
    final snapshot = snapshotWorld(before);
    final after = restoreWorld(snapshot);

    // Component truth survived (edge entity refs translated via persistent ids)
    final view = meaningView(after);
    expect(view.nodeCount, 3);
    expect(view.edgeCount, 2);
    final board = view.nodes.firstWhere((n) => n['id'] == 'board_1');
    expect((board['props'] as Map)['size'], 3);
    final cell = view.nodes.firstWhere((n) => n['id'] == 'cell_1');
    expect((cell['props'] as Map)['marker'], 'X');
    expect(
      view.edges.map((e) => '${e['from']}→${e['to']}'),
      containsAll(['board_1→cell_1', 'board_1→cell_2']),
    );

    // Derived state (meaning index + facet keywords) re-derived: same cut.
    final cutBefore = jsonEncode(
      meaningCut(before, focusIds: ['board_1'], maxNodes: 8, tokenBudget: 4096),
    );
    final cutAfter = jsonEncode(
      meaningCut(after, focusIds: ['board_1'], maxNodes: 8, tokenBudget: 4096),
    );
    expect(cutAfter, cutBefore);

    // The derived index resolves lookups post-restore.
    expect(hasMeaningNode(after, 'cell_2'), isTrue);
    expect(
      linkMeaning(after, from: 'cell_2', relation: 'next', to: 'cell_1'),
      isTrue,
    );
  });

  test('facet ray-cast finds meaning nodes after restore', () {
    final after = restoreWorld(snapshotWorld(_built()));
    final cut = meaningCut(after, query: 'top-left', maxNodes: 8);
    final ids = (cut['nodes'] as List).cast<Map>().map((n) => n['id']);
    expect(ids, contains('cell_1'));
  });
}
