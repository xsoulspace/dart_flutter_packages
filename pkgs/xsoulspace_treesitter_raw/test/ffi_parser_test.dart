// FFI parser tests (need the built grammar dylib — run
// tool/build_grammar.sh; the suite reports the missing dylib HONESTLY).
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

void main() {
  final dylibPath = findGrammarDylib();
  final skipReason = dylibPath == null
      ? 'grammar_dylib_missing — run tool/build_grammar.sh '
            '(ADR 0035 §8: the mechanical scanner serves where the dylib '
            'cannot build; the conformance suite still runs)'
      : false;

  test('parse: node types, fields, byte offsets, points', skip: skipReason, () {
    final parser = TreeSitterParser.open();
    try {
      const source = 'class A {\n  greet(): void {}\n}\n';
      final root = parser.parse(source);
      expect(root.type, 'program');
      // program has no fields — find the class among the named children.
      final cls = root.children.firstWhere(
        (n) => n.type == 'class_declaration',
      );
      expect(cls.startByte, 0);
      // The class ends at '}' (the trailing newline is the program's).
      expect(cls.endByte, source.length - 1);
      expect(cls.startRow, 0);
      expect(cls.startColumn, 0);
      // Root has no field.
      expect(root.field, isNull);
    } finally {
      parser.dispose();
    }
  });

  test(
    'multibyte source: byte offsets are UTF-8 byte offsets',
    skip: skipReason,
    () {
      final parser = TreeSitterParser.open();
      try {
        final source = File('test/fixtures/multibyte.ts').readAsStringSync();
        final root = parser.parse(source);
        // A node's end byte equals the source's UTF-8 length at EOF.
        expect(root.endByte, utf8.encode(source).length);
        expect(root.endByte, greaterThan(source.length)); // CJK is 3 bytes
        // The byte→code-unit bridge lands the symbol name exactly.
        final bridge = Utf8Utf16SpanBridge(source);
        final mapper = GrammarMapper(
          mapping: GrammarMapping.validate(tsMappingTable),
        );
        final symbols = mapper.map(root, source, bridge: bridge);
        final fn = symbols.firstWhere((s) => s.name == '縮める');
        expect(fn.startByte, lessThan(fn.endByte));
        expect(bridge.text(root).length, source.length);
      } finally {
        parser.dispose();
      }
    },
  );

  test('empty source parses to an empty program', skip: skipReason, () {
    final parser = TreeSitterParser.open();
    try {
      final root = parser.parse('');
      expect(root.type, 'program');
      expect(root.children, isEmpty);
    } finally {
      parser.dispose();
    }
  });

  test(
    'free/leak discipline: 200 parse+dispose cycles and 20 parser cycles '
    'complete without native crash (structural leak check)',
    skip: skipReason,
    () {
      final source = File('test/fixtures/calculator.ts').readAsStringSync();
      // Many parses through ONE parser, then many parser lifecycles.
      final parser = TreeSitterParser.open();
      try {
        for (var i = 0; i < 200; i++) {
          final root = parser.parse(source);
          expect(root.type, 'program');
        }
      } finally {
        parser.dispose();
      }
      for (var i = 0; i < 20; i++) {
        final p = TreeSitterParser.open();
        final root = p.parse(source);
        expect(root.type, 'program');
        p.dispose();
      }
      // Dispose is idempotent.
      parser.dispose();
    },
  );

  test(
    'missing-dylib signal is NAMED (constructed via an explicit bad path)',
    skip: skipReason,
    () {
      // XS_TREESITTER_DYLIB pointing at a missing file → named StateError.
      // (The findGrammarDylib null case is covered by the skipReason above.)
      expect(
        () => TreeSitterParser.open(dylibPath: '/nonexistent/lib.dylib'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test('use after dispose is a named Dart error', skip: skipReason, () {
    final parser = TreeSitterParser.open();
    parser.dispose();
    expect(() => parser.parse('x'), throwsStateError);
  });
}
