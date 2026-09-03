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

/// R7 hard cut (ADR 0023 §2): the tree is a RE-DERIVABLE projection target
/// and is NEVER snapshotted — snapshots carry beats, verdicts, budgets
/// only. The old parity expectation ("the tree survives restore") is the
/// contract this test now NEGATES: restore yields a tree-free world and
/// the tree owner re-derives (repo_etl scan/refresh — the R7c tick).
void main() {
  test(
    'snapshot → restore carries NO meaning tree (re-derivation contract); '
    'beats/verdicts/budgets still restore',
    () {
      final before = _built();
      final snapshot = snapshotWorld(before);
      final after = restoreWorld(snapshot);

      // The tree did NOT cross the persistence boundary.
      final view = meaningView(after);
      expect(view.nodeCount, 0, reason: 'the tree is re-derived, never restored');
      expect(view.edgeCount, 0);
      expect(hasMeaningNode(after, 'cell_2'), isFalse);

      // The snapshot ENVELOPE itself carries no meaning components.
      final encoded = jsonEncode(snapshot);
      expect(encoded, isNot(contains('MeaningNode')));
      expect(encoded, isNot(contains('MeaningProps')));
      expect(encoded, isNot(contains('MeaningEdge')));

      // Re-derivation (the host's mechanical tick) rebuilds the same tree:
      addMeaningNode(after, kind: 'board', label: 'tictactoe', props: {'size': 3});
      addMeaningNode(after, kind: 'cell', label: 'top-left');
      addMeaningNode(after, kind: 'cell', label: 'top-right');
      linkMeaning(after, from: 'board_1', relation: 'contains', to: 'cell_1');
      linkMeaning(after, from: 'board_1', relation: 'contains', to: 'cell_2');
      setMeaningProp(after, id: 'cell_1', key: 'marker', value: 'X');
      final cutBefore = meaningCut(
        _built(),
        focusIds: ['board_1'],
        maxNodes: 8,
        tokenBudget: 4096,
      );
      final cutAfter = meaningCut(
        after,
        focusIds: ['board_1'],
        maxNodes: 8,
        tokenBudget: 4096,
      );
      expect(jsonEncode(cutAfter), jsonEncode(cutBefore));
    },
  );

  test('facet ray-cast finds re-derived meaning nodes', () {
    final after = restoreWorld(snapshotWorld(_built()));
    // Re-derive (the R7c tick): the tree is world state again.
    addMeaningNode(after, kind: 'cell', label: 'top-left');
    final cut = meaningCut(after, query: 'top-left', maxNodes: 8);
    final ids = (cut['nodes'] as List).cast<Map>().map((n) => n['id']);
    expect(ids, contains('cell_1'));
  });
}
