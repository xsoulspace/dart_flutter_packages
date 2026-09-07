// Probe (throwaway): dump the tree-sitter tree + mapped symbols for a
// fixture to verify node types and expectations.
import 'dart:io';

import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

void main(List<String> args) {
  final fixturePath = args.first;
  final source = File(fixturePath).readAsStringSync();
  final parser = TreeSitterParser.open();
  try {
    final root = parser.parse(source);
    void dump(SourceNode n, String indent) {
      final field = n.field == null ? '' : ' [${n.field}]';
      // ignore: avoid_print
      print(
        '$indent${n.type}$field ${n.startByte}..${n.endByte} '
        '${n.startRow}:${n.startColumn}..${n.endRow}:${n.endColumn}',
      );
      for (final c in n.children) {
        dump(c, '$indent  ');
      }
    }

    dump(root, '');
    final bridge = Utf8Utf16SpanBridge(source);
    final mapper = GrammarMapper(
      mapping: GrammarMapping.validate(tsMappingTable),
    );
    final symbols = mapper.map(
      root,
      source,
      bridge: bridge,
      fileName: fixturePath.split('/').last,
    );
    // ignore: avoid_print
    print('--- mapped symbols ---');
    for (final s in symbols) {
      // ignore: avoid_print
      print(s);
    }
  } finally {
    parser.dispose();
  }
}
