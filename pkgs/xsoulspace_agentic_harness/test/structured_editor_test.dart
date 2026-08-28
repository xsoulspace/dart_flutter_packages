// ignore_for_file: lines_longer_than_80_chars

/// Structured-edit seam tests (LLM-free): one `act_with_project` tool,
/// closed enum sub-actions, AST hidden. The model picks a move; the harness
/// materializes + (optionally) runs. Deterministic.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/structured_editor.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Map<String, dynamic> _dec(Object? raw) {
  final r = raw is String ? jsonDecode(raw) : raw;
  return (r as Map).cast<String, dynamic>();
}

void main() {
  test('list / add / link / set_prop build a project graph', () async {
    final doc = StructuredDoc();
    final tool = actWithProjectTool(
      doc: () => doc,
      materialize: () async => {'path': 'main.dart', 'content': 'void main(){}'},
    );
    // list at start is empty
    var r = _dec(await tool.execute({'action': 'list'}));
    expect((r['nodes'] as List), isEmpty);

    // add a board + cells
    _dec(await tool.execute({'action': 'add', 'kind': 'board', 'label': 'tictactoe'}));
    final board = doc.nodes.values.first;
    _dec(await tool.execute({'action': 'add', 'kind': 'cell', 'label': 'top-left'}));
    final cell = doc.nodes.values.last;

    expect(doc.nodes.length, 2);

    // link board -> cell
    r = _dec(await tool.execute({
      'action': 'link',
      'from': board.id,
      'relation': 'contains',
      'to': cell.id,
    }));
    expect(r['ok'], true);

    // set cell marker = X
    r = _dec(await tool.execute({
      'action': 'set_prop',
      'id': cell.id,
      'key': 'marker',
      'value': 'X',
    }));
    expect(r['ok'], true);
    expect(doc.nodes[cell.id]!.props['marker'], 'X');
  });

  test('materialize returns target source (host program writes it)', () async {
    var called = false;
    final tool = actWithProjectTool(
      doc: () => StructuredDoc(),
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

  test('sub-action surface is closed + countable (stewardship probe)', () {
    expect(actWithProjectSubActions, [
      'list', 'add', 'link', 'set_prop', 'materialize',
    ]);
    expect(actWithProjectSubActions.toSet().length, 5);
  });

  test('unknown action returns a structured error, not a throw', () async {
    final tool = actWithProjectTool(
      doc: () => StructuredDoc(),
      materialize: () async => {},
    );
    final r = _dec(await tool.execute({'action': 'obliterate'}));
    expect(r['error'], isNotNull);
  });
}

// referenced only for API reachability of the real alias
const _ = StructuredDoc;