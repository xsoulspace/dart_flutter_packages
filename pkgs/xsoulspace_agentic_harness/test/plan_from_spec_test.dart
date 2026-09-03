// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage G4 — the AE ETL seam end-to-end, deterministic + LLM-free:
///
///   sentence → AE canonical pack (fixture) → agentic_executables_wire
///   canonicalToMeaningTree → planFromSpec (world state + Goal/Steps)
///   → act_with_project + run-graded loop → verify tier → idle.
///
/// The AE leg is a fixture here (real `ae canonical import-spec` is optional
/// and additive); the wire conversion and the world import are the parts
/// this repo owns and they must be deterministic.
library;

import 'package:agentic_executables_wire/agentic_executables_wire.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/build_gates.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

const _ecsPack = {
  'schema': 'ae.canonical.v3',
  'meta': {
    'schema': 'ae.canonical.meta.v1',
    'concept': 'ecs',
    'version': 1,
    'title': 'Entity-Component-System (canonical)',
  },
  'matrix': {
    'schema': 'ae.canonical_matrix.v1',
    'concept': 'ecs',
    'version': 1,
    'features': [
      {
        'id': 'entity.create',
        'spec': 'An entity is created with a unique opaque handle.',
      },
      {
        'id': 'system.tick',
        'spec': 'Systems run in declared order each tick.',
      },
      {
        'id': 'query.iterate',
        'spec': 'Queries iterate matching archetypes.',
      },
    ],
  },
};

void main() {
  test('planFromSpec: canonical tree becomes world state with canonical ids',
      () {
    final world = World()..addPlugin(AgentPlugin());
    planFromSpec(
      world,
      spec: canonicalToMeaningTree(_ecsPack),
      goalText: 'Build an ECS tick loop that runs.',
    );

    // ONE id vocabulary: canonical ids live in the world's meaning tree.
    final view = meaningView(world);
    final ids = view.nodes.map((n) => n['id']).toSet();
    expect(
      ids,
      containsAll(['entity', 'system', 'query', 'entity.create', 'system.tick']),
    );
    expect(view.nodeCount, 6); // 3 concepts + 3 features
    expect(view.edgeCount, 3); // contains: concept → feature

    // Feature props carry the spec cells verbatim.
    final create = view.nodes.firstWhere((n) => n['id'] == 'entity.create');
    expect((create['props'] as Map)['spec'], contains('unique opaque handle'));

    // Goal + one mechanical step per feature row (sorted by id).
    final goals = world.query<Goal>().toList();
    expect(goals, hasLength(1));
    expect(goals.single.$2.text, 'Build an ECS tick loop that runs.');
    final steps = world.query2<StepClaim, StepIndex>().toList()
      ..sort((a, b) => a.$3.value.compareTo(b.$3.value));
    expect(steps.map((s) => s.$2.text.split(':').first),
        ['entity.create', 'query.iterate', 'system.tick']);
    final actions = world.query<StepAction>().toList();
    expect(
      actions.every((a) => a.$2.toolName == 'act_with_project'),
      isTrue,
    );
  });

  test('the imported tree is a real meaning tree: ray-cast, cut, snapshot', () {
    final world = World()..addPlugin(AgentPlugin());
    planFromSpec(
      world,
      spec: canonicalToMeaningTree(_ecsPack),
      goalText: 'Build an ECS tick loop that runs.',
    );

    // Facet ray-cast reaches into prop text (spec cells)…
    final cut = meaningCut(world, query: 'opaque handle', maxNodes: 8);
    final cutIds = (cut['nodes'] as List).cast<Map>().map((n) => n['id']);
    expect(cutIds, contains('entity.create'));

    // R7 hard cut (ADR 0023 §2): the tree does NOT round-trip through the
    // snapshot — it is RE-DERIVABLE. The snapshot carries beats/verdicts/
    // budgets only; the owner re-derives (here: re-importing the same
    // canonical spec into the restored world).
    final after = restoreWorld(snapshotWorld(world));
    expect(meaningView(after).nodeCount, 0,
        reason: 'the tree is re-derived, never restored');
    planFromSpec(
      after,
      spec: canonicalToMeaningTree(_ecsPack),
      goalText: 'Build an ECS tick loop that runs.',
    );
    final restored = meaningView(after);
    expect(restored.nodeCount, 6);
    expect(
      restored.edges.map((e) => '${e['from']}→${e['to']}'),
      contains('entity→entity.create'),
    );

    // Post-restore, the same query finds the same node (derived index rebuilt).
    final recut = meaningCut(after, query: 'opaque handle', maxNodes: 8);
    expect(
      (recut['nodes'] as List).cast<Map>().map((n) => n['id']),
      contains('entity.create'),
    );
  });

  test('importing the same spec twice fails loudly (id collision guard)', () {
    final world = World()..addPlugin(AgentPlugin());
    final spec = canonicalToMeaningTree(_ecsPack);
    planFromSpec(world, spec: spec, goalText: 'a');
    expect(
      () => planFromSpec(world, spec: spec, goalText: 'b'),
      throwsArgumentError,
    );
  });
}
