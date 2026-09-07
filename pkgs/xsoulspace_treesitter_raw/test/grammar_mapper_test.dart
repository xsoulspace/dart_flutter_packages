// GrammarMapper tests (pure Dart — hand-built SourceNode trees, no FFI):
// memberOf resolution, descendant name resolution, and the NAMED
// load/runtime validation errors (ADR 0035 §8 item 3).
import 'package:test/test.dart';
import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

SourceNode leaf(String type, {String? field, required int s, required int e}) =>
    SourceNode(
      type: type,
      field: field,
      startByte: s,
      endByte: e,
      startRow: 0,
      startColumn: s,
      endRow: 0,
      endColumn: e,
      children: const [],
    );

/// A `lexical_declaration` whose name lives on the child
/// `variable_declarator` (the descendant-name-resolution case).
SourceNode lexDecl(
  String name, {
  required String? field,
  required int s,
  required int e,
}) => SourceNode(
  type: 'lexical_declaration',
  field: field,
  startByte: s,
  endByte: e,
  startRow: 0,
  startColumn: s,
  endRow: 0,
  endColumn: e,
  children: [
    SourceNode(
      type: 'variable_declarator',
      field: null,
      startByte: s,
      endByte: e,
      startRow: 0,
      startColumn: s,
      endRow: 0,
      endColumn: e,
      children: [leaf('property_identifier', field: 'name', s: s, e: e)],
    ),
  ],
);

GrammarMapper mapperFor(Map<String, GrammarNodeSpec> table) =>
    GrammarMapper(mapping: GrammarMapping.validate(table));

/// Matches any exception whose toString contains [fragment] (the NAMED
/// error codes under test).
Matcher namedError(String fragment) => predicate<Object>(
  (e) => e.toString().contains(fragment),
  'an error naming "$fragment"',
);

const baseTable = <String, GrammarNodeSpec>{
  'program': GrammarNodeSpec(kind: SymbolKind.file),
  'class_declaration': GrammarNodeSpec(
    kind: SymbolKind.sym,
    nameField: 'name',
    memberOf: 'file',
  ),
  'method_definition': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'parent',
  ),
  'lexical_declaration': GrammarNodeSpec(
    kind: SymbolKind.member,
    nameField: 'name',
    memberOf: 'file',
  ),
};

void main() {
  group('GrammarMapping.load-time validation', () {
    test('empty table = named error', () {
      expect(
        () => GrammarMapping.validate(const {}),
        throwsA(namedError('empty_mapping_table')),
      );
    });

    test('sym without nameField = named error', () {
      expect(
        () => GrammarMapping.validate(const {
          'x': GrammarNodeSpec(kind: SymbolKind.sym),
        }),
        throwsA(namedError('missing_name_field:x')),
      );
    });

    test('member without a legal memberOf = named error', () {
      expect(
        () => GrammarMapping.validate(const {
          'x': GrammarNodeSpec(kind: SymbolKind.member, nameField: 'name'),
        }),
        throwsA(namedError('illegal_member_of:x')),
      );
    });

    test('file kind with nameField/memberOf = named error', () {
      expect(
        () => GrammarMapping.validate(const {
          'x': GrammarNodeSpec(kind: SymbolKind.file, nameField: 'name'),
        }),
        throwsA(namedError('file_kind_with_attachments:x')),
      );
    });

    test('memberOf cycle = named error', () {
      const table = <String, GrammarNodeSpec>{
        'a': GrammarNodeSpec(
          kind: SymbolKind.member,
          nameField: 'name',
          memberOf: 'ancestor:b',
        ),
        'b': GrammarNodeSpec(
          kind: SymbolKind.member,
          nameField: 'name',
          memberOf: 'ancestor:a',
        ),
      };
      expect(
        () => GrammarMapping.validate(table),
        throwsA(namedError('member_of_cycle:a')),
      );
    });

    test('self-referencing ancestor = a named cycle error too', () {
      const table = <String, GrammarNodeSpec>{
        'a': GrammarNodeSpec(
          kind: SymbolKind.member,
          nameField: 'name',
          memberOf: 'ancestor:a',
        ),
      };
      expect(
        () => GrammarMapping.validate(table),
        throwsA(namedError('member_of_cycle:a')),
      );
    });
  });

  group('member attachment resolution', () {
    // program { class_declaration Calculator { method_definition greet } }
    final tree = SourceNode(
      type: 'program',
      field: null,
      startByte: 0,
      endByte: 100,
      startRow: 0,
      startColumn: 0,
      endRow: 0,
      endColumn: 100,
      children: [
        SourceNode(
          type: 'class_declaration',
          field: 'declaration',
          startByte: 0,
          endByte: 100,
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 100,
          children: [leaf('property_identifier', field: 'name', s: 6, e: 16)],
        ),
      ],
    );
    // The same class, with the method carrying its `name` field child.
    final namedMethod = SourceNode(
      type: 'class_declaration',
      field: 'declaration',
      startByte: 0,
      endByte: 100,
      startRow: 0,
      startColumn: 0,
      endRow: 0,
      endColumn: 100,
      children: [
        leaf('property_identifier', field: 'name', s: 6, e: 16),
        SourceNode(
          type: 'method_definition',
          field: 'body',
          startByte: 20,
          endByte: 40,
          startRow: 0,
          startColumn: 20,
          endRow: 0,
          endColumn: 40,
          children: [leaf('property_identifier', field: 'name', s: 20, e: 25)],
        ),
      ],
    );

    test('sym resolves its nameField; top-level sym has no parent', () {
      final symbols = mapperFor(
        baseTable,
      ).map(tree, 'x' * 100, fileName: 'f.ts');
      final cls = symbols.singleWhere((s) => s.name == 'x' * 10);
      expect(cls.kind, SymbolKind.sym);
      expect(cls.parentName, isNull);
    });

    test("member with memberOf 'parent' attaches to the mapped class", () {
      final symbols = mapperFor(
        baseTable,
      ).map(namedMethod, 'x' * 100, fileName: 'f.ts');
      final greet = symbols.singleWhere((s) => s.name == 'x' * 5);
      expect(greet.kind, SymbolKind.member);
      expect(greet.parentName, 'x' * 10); // the class's name slice
    });

    test('descendant name resolution: lexical_declaration → declarator', () {
      final tree = SourceNode(
        type: 'program',
        field: null,
        startByte: 0,
        endByte: 30,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 30,
        children: [lexDecl('multiply', field: null, s: 0, e: 30)],
      );
      final symbols = mapperFor(
        baseTable,
      ).map(tree, 'x' * 30, fileName: 'f.ts');
      final m = symbols.singleWhere((s) => s.name == 'x' * 30);
      expect(m.kind, SymbolKind.member);
      // memberOf 'file' with no enclosing symbol → attached to the file.
      expect(m.parentName, isNull);
    });

    test("member nested in a function resolves 'file' to that symbol", () {
      const fnTable = <String, GrammarNodeSpec>{
        ...baseTable,
        'function_declaration': GrammarNodeSpec(
          kind: SymbolKind.sym,
          nameField: 'name',
          memberOf: 'file',
        ),
      };
      final tree = SourceNode(
        type: 'program',
        field: null,
        startByte: 0,
        endByte: 60,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 60,
        children: [
          SourceNode(
            type: 'function_declaration',
            field: null,
            startByte: 0,
            endByte: 60,
            startRow: 0,
            startColumn: 0,
            endRow: 0,
            endColumn: 60,
            children: [
              leaf('property_identifier', field: 'name', s: 9, e: 17),
              lexDecl('inner', field: 'body', s: 20, e: 50),
            ],
          ),
        ],
      );
      final symbols = mapperFor(fnTable).map(tree, 'x' * 60, fileName: 'f.ts');
      final inner = symbols.singleWhere((s) => s.name == 'x' * 30);
      expect(inner.kind, SymbolKind.member);
      // Attached to the enclosing function symbol (its name slice is 8 'x').
      expect(inner.parentName, 'x' * 8);
    });
  });

  group('runtime named errors', () {
    test('unresolved_name_field is NAMED', () {
      final tree = SourceNode(
        type: 'program',
        field: null,
        startByte: 0,
        endByte: 10,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 10,
        children: [
          // A class_declaration WITHOUT a name field child.
          leaf('class_declaration', field: null, s: 0, e: 10),
        ],
      );
      expect(
        () => mapperFor(baseTable).map(tree, 'x' * 10, fileName: 'f.ts'),
        throwsA(namedError('unresolved_name_field:class_declaration')),
      );
    });

    test(
      "unresolved_member_parent (memberOf 'parent' at top level) is NAMED",
      () {
        const table = <String, GrammarNodeSpec>{
          'program': GrammarNodeSpec(kind: SymbolKind.file),
          'method_definition': GrammarNodeSpec(
            kind: SymbolKind.member,
            nameField: 'name',
            memberOf: 'parent',
          ),
        };
        final tree = SourceNode(
          type: 'program',
          field: null,
          startByte: 0,
          endByte: 10,
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 10,
          children: [
            SourceNode(
              type: 'method_definition',
              field: null,
              startByte: 0,
              endByte: 10,
              startRow: 0,
              startColumn: 0,
              endRow: 0,
              endColumn: 10,
              children: [
                leaf('property_identifier', field: 'name', s: 0, e: 5),
              ],
            ),
          ],
        );
        expect(
          () => GrammarMapper(
            mapping: GrammarMapping.validate(table),
          ).map(tree, 'x' * 10, fileName: 'f.ts'),
          throwsA(namedError('unresolved_member_parent:method_definition')),
        );
      },
    );

    test(
      "unknown_ancestor_type ('ancestor:<Type>' not a table key) is NAMED",
      () {
        const table = <String, GrammarNodeSpec>{
          'program': GrammarNodeSpec(kind: SymbolKind.file),
          'method_definition': GrammarNodeSpec(
            kind: SymbolKind.member,
            nameField: 'name',
            memberOf: 'ancestor:nonexistent_type',
          ),
        };
        final tree = SourceNode(
          type: 'program',
          field: null,
          startByte: 0,
          endByte: 10,
          startRow: 0,
          startColumn: 0,
          endRow: 0,
          endColumn: 10,
          children: [
            SourceNode(
              type: 'method_definition',
              field: null,
              startByte: 0,
              endByte: 10,
              startRow: 0,
              startColumn: 0,
              endRow: 0,
              endColumn: 10,
              children: [
                leaf('property_identifier', field: 'name', s: 0, e: 5),
              ],
            ),
          ],
        );
        expect(
          () => GrammarMapper(
            mapping: GrammarMapping.validate(table),
          ).map(tree, 'x' * 10, fileName: 'f.ts'),
          throwsA(namedError('unknown_ancestor_type:method_definition')),
        );
      },
    );

    test('unresolved_ancestor (type never encloses the node) is NAMED', () {
      const table = <String, GrammarNodeSpec>{
        'program': GrammarNodeSpec(kind: SymbolKind.file),
        'class_declaration': GrammarNodeSpec(
          kind: SymbolKind.sym,
          nameField: 'name',
          memberOf: 'file',
        ),
        'method_definition': GrammarNodeSpec(
          kind: SymbolKind.member,
          nameField: 'name',
          memberOf: 'ancestor:class_declaration',
        ),
      };
      final tree = SourceNode(
        type: 'program',
        field: null,
        startByte: 0,
        endByte: 40,
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 40,
        children: [
          // method_definition NOT inside any class_declaration.
          SourceNode(
            type: 'method_definition',
            field: null,
            startByte: 0,
            endByte: 10,
            startRow: 0,
            startColumn: 0,
            endRow: 0,
            endColumn: 10,
            children: [leaf('property_identifier', field: 'name', s: 0, e: 5)],
          ),
        ],
      );
      expect(
        () => GrammarMapper(
          mapping: GrammarMapping.validate(table),
        ).map(tree, 'x' * 40, fileName: 'f.ts'),
        throwsA(namedError('unresolved_ancestor:method_definition')),
      );
    });
  });
}
