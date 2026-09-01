// ignore_for_file: lines_longer_than_80_chars

/// `act_with_project` seam tests (LLM-free): ONE tool, closed enum
/// sub-actions, meaning tree as ECS world state (PLAN Stage F), AST hidden.
/// The model picks a move; every move returns a budgeted cut of the tree;
/// the harness materializes + (optionally) runs. Deterministic.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/act_with_project.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Map<String, dynamic> _dec(Object? raw) {
  final r = raw is String ? jsonDecode(raw) : raw;
  return (r as Map).cast<String, dynamic>();
}

World _world() => World()..addPlugin(AgentPlugin());

void main() {
  test('list / add / link / set_prop build a project graph (world state)', () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {'path': 'main.dart', 'content': 'void main(){}'},
    );
    // list at start is empty
    var r = _dec(await tool.execute({'action': 'list'}));
    expect((r['nodes'] as List), isEmpty);

    // add a board + cells
    r = _dec(await tool.execute({'action': 'add', 'kind': 'board', 'label': 'tictactoe'}));
    final boardId = r['id'] as String;
    expect(boardId, 'board_1');
    r = _dec(await tool.execute({'action': 'add', 'kind': 'cell', 'label': 'top-left'}));
    final cellId = r['id'] as String;

    final view = r['view'] as Map;
    expect((view['total'] as num), 2);

    // link board -> cell
    r = _dec(await tool.execute({
      'action': 'link',
      'from': boardId,
      'relation': 'contains',
      'to': cellId,
    }));
    expect(r['ok'], true);

    // set cell marker = X
    r = _dec(await tool.execute({
      'action': 'set_prop',
      'id': cellId,
      'key': 'marker',
      'value': 'X',
    }));
    expect(r['ok'], true);
    final nodes = ((r['view'] as Map)['nodes'] as List).cast<Map>();
    final cell = nodes.firstWhere((n) => n['id'] == cellId);
    expect((cell['props'] as Map)['marker'], 'X');
  });

  test('every move returns a budgeted cut with total + truncated (F2)', () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {},
      cutMaxNodes: 4,
      cutTokenBudget: 4096,
    );
    for (var i = 0; i < 10; i++) {
      await tool.execute({'action': 'add', 'kind': 'cell', 'label': 'cell $i'});
    }
    final r = _dec(await tool.execute({'action': 'list'}));
    expect((r['nodes'] as List).length, 4); // capped
    expect(r['total'], 10); // true size reported
    expect(r['truncated'], true); // green-screen fact present
  });

  test('materialize returns target source (host program writes it)', () async {
    var called = false;
    final tool = actWithProjectTool(
      world: _world(),
      materialize: () async {
        called = true;
        return {
          'path': 'main.dart',
          'content': 'void main() { print("board ok"); }',
          'runs': true,
        };
      },
    );
    final r = _dec(await tool.execute({'action': 'materialize'}));
    expect(called, isTrue);
    expect(r['runs'], isTrue);
    expect(r['path'], 'main.dart');
  });

  test('link to an unknown node fails with a structured error', () async {
    final tool = actWithProjectTool(
      world: _world(),
      materialize: () async => {},
    );
    await tool.execute({'action': 'add', 'kind': 'a', 'label': 'A'});
    final r = _dec(await tool.execute({
      'action': 'link', 'from': 'a_1', 'relation': 'x', 'to': 'ghost_1',
    }));
    expect(r['ok'], false);
    expect(r['error'], isNotNull);
  });

  test('sub-action surface is closed + countable (stewardship probe)', () {
    expect(actWithProjectSubActions, [
      'list', 'add', 'link', 'set_prop', 'materialize',
      // Macros (J1, D3 gate fired): host-program composite moves. Intent-
      // level repair lives on intent_define (`redefine_chain`) — one verb
      // per domain, no near-tool collisions (ADR 0016).
      'add_chain', 'link_chain',
    ]);
    expect(actWithProjectSubActions.toSet().length, 7);
    // The intent surface carries the intent-level macro.
    expect(intentDefineActions, ['define', 'list', 'redefine_chain']);
  });

  test('unknown action returns a structured error, not a throw', () async {
    final tool = actWithProjectTool(
      world: _world(),
      materialize: () async => {},
    );
    final r = _dec(await tool.execute({'action': 'obliterate'}));
    expect(r['error'], isNotNull);
  });

  // ---- Zoom: the view cut is a ray PROJECTION (per-decision strategy) ----
  test('move acks zoom to point: only what changed, O(1) in tree size',
      () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {},
    );
    // Grow a tree well past the fill threshold.
    String lastId = '';
    for (var i = 0; i < 8; i++) {
      final r = _dec(await tool
          .execute({'action': 'add', 'kind': 'cell', 'label': 'cell_$i'}));
      lastId = r['id'] as String;
    }
    final view = _dec(await tool.execute({
      'action': 'add', 'kind': 'cell', 'label': 'the-touched-one',
    }));
    expect(view['ok'], true);
    final cut = view['view'] as Map;
    expect(cut['zoom'], 'point');
    final nodes = (cut['nodes'] as List).cast<Map>();
    // The point zoom admits ONLY the touched node — no fill, no neighbors.
    expect(nodes, hasLength(1));
    expect(nodes.first['id'], 'cell_9');
    expect(nodes.first['label'], 'the-touched-one');
    // But the green-screen fact survives: the model knows what it can't see.
    expect(cut['total'], 9);
    expect(cut['truncated'], true);
  });

  test('point zoom edges carry full from/to handles (zoom out later)',
      () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {},
    );
    await tool.execute({'action': 'add', 'kind': 'board', 'label': 'b'});
    final linkR = _dec(await tool
        .execute({'action': 'add', 'kind': 'cell', 'label': 'c1'}));
    await tool.execute({
      'action': 'link',
      'from': 'board_1', 'relation': 'contains', 'to': linkR['id'],
    });
    // Now touch ONLY the board: the point cut must still show the edge to
    // the (un-admitted) cell via its stable handle.
    final view = _dec(await tool.execute({
      'action': 'set_prop', 'id': 'board_1', 'key': 'size', 'value': '3',
    }));
    final cut = view['view'] as Map;
    final nodes = (cut['nodes'] as List).cast<Map>();
    expect(nodes, hasLength(1));
    expect(nodes.first['id'], 'board_1');
    final edges = (cut['edges'] as List).cast<Map>();
    expect(edges, isNotEmpty);
    expect(
      edges.any((e) => e['from'] == 'board_1' && e['to'] == 'cell_1'),
      isTrue,
    );
  });

  test('list zooms out: local (default), region (2-hop), summary',
      () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {},
    );
    // book --chapters--> ch1 --paragraphs--> p1 --lines--> l1
    await tool.execute({'action': 'add', 'kind': 'book', 'label': 'b'});
    await tool.execute({'action': 'add', 'kind': 'chapter', 'label': 'c1'});
    await tool.execute({'action': 'add', 'kind': 'paragraph', 'label': 'p1'});
    await tool.execute({'action': 'add', 'kind': 'line', 'label': 'l1'});
    await tool.execute({
      'action': 'link', 'from': 'book_1', 'relation': 'chapters',
      'to': 'chapter_1',
    });
    await tool.execute({
      'action': 'link', 'from': 'chapter_1', 'relation': 'paragraphs',
      'to': 'paragraph_1',
    });
    await tool.execute({
      'action': 'link', 'from': 'paragraph_1', 'relation': 'lines',
      'to': 'line_1',
    });

    // local (default): focus + 1-hop — book_1, chapter_1.
    final local = _dec(await tool.execute({
      'action': 'list', 'zoom': 'local', 'query': 'book',
    }));
    expect(local['zoom'], 'local');
    final localIds =
        (local['nodes'] as List).cast<Map>().map((n) => n['id']).toSet();
    expect(localIds, containsAll(['book_1', 'chapter_1']));

    // region: 2-hop — book_1, chapter_1, paragraph_1.
    final region = _dec(await tool.execute({
      'action': 'list', 'zoom': 'region', 'query': 'book',
    }));
    expect(region['zoom'], 'region');
    final regionIds =
        (region['nodes'] as List).cast<Map>().map((n) => n['id']).toSet();
    expect(regionIds, containsAll(['book_1', 'chapter_1', 'paragraph_1']));
    expect(regionIds, isNot(contains('line_1')));

    // summary: NO node details — the structuralized bigger picture.
    final summary = _dec(
        await tool.execute({'action': 'list', 'zoom': 'summary'}));
    expect(summary['zoom'], 'summary');
    expect(summary.containsKey('nodes'), isFalse);
    final kinds = (summary['kinds'] as Map).cast<String, dynamic>();
    expect(kinds, {
      'book': 1, 'chapter': 1, 'paragraph': 1, 'line': 1,
    });
    final agg = (summary['edges'] as List).cast<Map>();
    expect(
      agg.any((e) =>
          e['edge'] == 'book --chapters--> chapter' && e['count'] == 1),
      isTrue,
    );
    // The green-screen fact: total is the TRUE tree size.
    expect(summary['total'], 4);
  });

  test('zoom vocabulary is closed + countable (stewardship probe)', () {
    expect(meaningZoomLevels, ['point', 'local', 'region', 'summary']);
  });

  test('ray-cast hits are SEEDS: query hits expand their neighborhood',
      () async {
    final world = _world();
    final tool = actWithProjectTool(
      world: world,
      materialize: () async => {},
    );
    // Labels carry the search keyword so the facet ray-cast finds chapter_1.
    await tool.execute({'action': 'add', 'kind': 'chapter', 'label': 'chapter one'});
    await tool.execute({'action': 'add', 'kind': 'paragraph', 'label': 'paragraph one'});
    await tool.execute({
      'action': 'link', 'from': 'chapter_1', 'relation': 'paragraphs',
      'to': 'paragraph_1',
    });
    // Region zoom on the query hit must pull the hit + 2-hop (here: 1 link).
    final region = _dec(await tool.execute({
      'action': 'list', 'zoom': 'region', 'query': 'chapter',
    }));
    final ids =
        (region['nodes'] as List).cast<Map>().map((n) => n['id']).toSet();
    expect(ids, containsAll(['chapter_1', 'paragraph_1']));
  });

  // ---- J1 macros: one selection, host does the heavy lifting ----
  test('add_chain macro: whole chain in one move, ids assigned, then-wired',
      () async {
    final world = _world();
    final tool = actWithProjectTool(world: world, materialize: () async => {});
    defineIntent(world, name: 'save_url');
    final r = _dec(await tool.execute({
      'action': 'add_chain',
      'specs': [
        {'label': 'load_arg', 'a': 'url'},
        {'label': 'starts_with', 'b': 'http'},
        {'label': 'return'},
      ],
    }));
    expect(r['ok'], true);
    final ids = (r['ids'] as List).cast<String>();
    expect(ids, ['op_1', 'op_2', 'op_3']);
    expect(r['added'], 3);
    // The validator reports the intent as defined-but-unwired (no impl edge
    // yet) — actionable data, exactly what the model should wire next.
    expect(r['problems'], ['save_url: no meaning executor for intent: save_url']);
    // then-wiring happened: interpreter walks load_arg → starts_with → return.
    final out = interpretMeaningProgram(
      world, 'save_url', <String, dynamic>{}, <String, dynamic>{},
    );
    // impl not linked yet — chain exists but intent not wired.
    expect((out['_result'] as Map)['error'],
        'no meaning executor for intent: save_url');
  });

  test('link_chain macro: many edges in one move, per-edge results', () async {
    final world = _world();
    final tool = actWithProjectTool(world: world, materialize: () async => {});
    defineIntent(world, name: 'save_url');
    final chain = _dec(await tool.execute({
      'action': 'add_chain',
      'specs': [
        {'label': 'load_arg', 'a': 'url'},
        {'label': 'starts_with', 'b': 'http'},
        {'label': 'return'},
      ],
    }));
    final ids = (chain['ids'] as List).cast<String>();
    final r = _dec(await tool.execute({
      'action': 'link_chain',
      'edges': [
        {'from': 'save_url', 'relation': 'impl', 'to': ids.first},
        {'from': ids.last, 'relation': 'then', 'to': 'op_Nope'},
      ],
    }));
    expect(r['ok'], false); // second edge is dangling
    final results = (r['results'] as List).cast<Map>();
    expect(results.first['ok'], true);
    expect(results.last['ok'], false);
    // The good edge still landed; oracle validates the chain.
    final problems = validateMeaningProgram(world);
    expect(problems, isEmpty);
  });

}
