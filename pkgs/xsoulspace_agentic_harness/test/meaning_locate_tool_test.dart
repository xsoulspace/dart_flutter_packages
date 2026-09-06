// ignore_for_file: lines_longer_than_80_chars

/// The DISCOVERY RAY gate (ADR 0014 §2 re-based on the meaning tree):
/// `meaning_locate` answers "where is X?" from the map-graph in one
/// token-bounded call — class-agnostic (any meaning node label), ranked
/// (exact > prefix > contains), usage counts from the tree's own refs
/// edges. This is the verb that makes grep unnecessary: ids for
/// zoom/impact come FROM locate rows.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart'
    show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_agentic_harness/src/tools/meaning_locate_tool.dart';

void main() {
  late World world;
  setUp(() {
    world = World()..addPlugin(AgentPlugin());
    // A tiny meaning graph: two symbols (one referenced), an intent, a
    // section, and a keypath — locate must be class-agnostic over them.
    addMeaningNode(
      world,
      kind: 'symbol',
      label: 'refreshFsTier',
      id: 'sym_a',
      props: {'file': 'lib/fs_etl.dart', 'line': 270},
    );
    addMeaningNode(
      world,
      kind: 'symbol',
      label: 'refreshFsTierTreeDriven',
      id: 'sym_b',
      props: {'file': 'lib/fs_etl.dart', 'line': 300},
    );
    addMeaningNode(
      world,
      kind: 'symbol',
      label: 'unrelatedThing',
      id: 'sym_c',
      props: {'file': 'lib/other.dart', 'line': 1},
    );
    addMeaningNode(
      world,
      kind: 'intent',
      label: 'reconcile_workspace',
      id: 'intent_1',
    );
    addMeaningNode(
      world,
      kind: 'section',
      label: 'Refresh tick',
      id: 'sec_1',
      props: {'path': 'docs/PLAN.md'},
    );
    addMeaningNode(world, kind: 'key', label: 'tick.interval', id: 'key_1');
    // refs edges: two files reference sym_a, one references sym_b.
    for (final f in ['f_a', 'f_b', 'f_c']) {
      addMeaningNode(world, kind: 'file', label: f, id: f);
    }
    linkMeaning(world, from: 'f_a', relation: 'refs', to: 'sym_a');
    linkMeaning(world, from: 'f_b', relation: 'refs', to: 'sym_a');
    linkMeaning(world, from: 'f_c', relation: 'refs', to: 'sym_b');
  });

  Future<Map<String, dynamic>> locate(String query, {int? maxRows}) async {
    final tool = meaningLocateTool(world);
    final out = await tool.execute({
      'query': query,
      if (maxRows != null) 'maxRows': maxRows,
    });
    return jsonDecode(out ?? '{}') as Map<String, dynamic>;
  }

  test('exact match first; class-agnostic across symbol/intent/section/key',
      () async {
    final r = await locate('reconcile_workspace');
    expect(r['ok'], true, reason: '$r');
    final rows = r['rows'] as List;
    expect(rows, isNotEmpty);
    expect((rows.first as Map)['id'], 'intent_1');
    expect((rows.first as Map)['kind'], 'intent');
  });

  test('prefix beats containment; refs counts ride the rows', () async {
    final r = await locate('refreshFsTier');
    final rows = (r['rows'] as List).cast<Map>();
    // Both symbols match; exact-id ordering puts the exact-prefixed one first.
    expect(rows.first['id'], 'sym_a', reason: '$r');
    expect(rows.first['refs'], 2, reason: 'two files reference sym_a: $r');
    final b = rows.where((row) => row['id'] == 'sym_b').toList();
    expect(b, isNotEmpty);
    expect(b.first['refs'], 1);
    // File rows that reference the hit symbols are NOT returned — the ray
    // answers with the matched MEANINGS, usages ride as counts.
    expect(rows.every((row) => row['kind'] != 'file'), isTrue, reason: '$r');
  });

  test('token-bounded: maxRows caps with an honest truncation fact', () async {
    final r = await locate('refreshFsTier', maxRows: 1);
    expect(r['truncated'], true, reason: '$r');
    expect((r['rows'] as List).length, 1);
    expect(r['total'], greaterThan(1));
  });

  test('no match and empty tree are named data, never guesses', () async {
    final none = await locate('zzz_no_such_meaning');
    expect(none['ok'], true);
    expect(none['total'], 0);
    expect((none['hint'] as String), isNotEmpty);

    final empty = meaningLocateTool(World()..addPlugin(AgentPlugin()));
    final out = jsonDecode(await empty.execute({'query': 'x'}) ?? '{}')
        as Map<String, dynamic>;
    expect(out, contains('error'));
    expect(out['error'], 'tree_empty');
  });

  test('query required — the ray refuses to guess', () async {
    final tool = meaningLocateTool(world);
    final out = jsonDecode(await tool.execute({}) ?? '{}')
        as Map<String, dynamic>;
    expect(out['error'], 'query_required');
  });
}
