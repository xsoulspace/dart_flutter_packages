// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 3 — the generic query+map interpreter, written ONCE:
/// ONE walker driven by a node-kind MAPPING TABLE (data):
/// `{grammarNodeType: {kind: sym|member|file, nameField, memberOf}}`.
///
/// Per language = a table + fixtures (the TS table lives in
/// ts_mapping_table.dart). The table is validated AT LOAD: unknown
/// node types referenced by `memberOf: ancestor:<type>` (that never appear
/// in fixtures), unresolved name fields at runtime, and cycles in
/// `memberOf` chains are NAMED errors — never silent.
///
/// SCOPE NOTE (ADR 0035 §8, recorded honestly): the spike needs NO
/// tree-sitter query engine (S-expression queries). Field-based extraction
/// (nameField + memberOf) covers the symbol map; if a measured row later
/// needs captures (e.g. refs edges — a declared escape until then), the
/// query engine lands behind this same GrammarMapper seam.
library;

import 'dart:convert';

import 'source_parser.dart';
import 'span_bridge.dart';

/// The mapped symbol kinds (the meaning-node families the ETL consumes:
/// file → `file` node facts; sym → `sym_*` nodes; member → member symbols
/// under their declaring parent — ADR 0035 §8, member symbols day one so
/// `replace_member_body` has a node to address).
enum SymbolKind { file, sym, member }

/// One mapping-table entry (DATA, per language).
class GrammarNodeSpec {
  const GrammarNodeSpec({required this.kind, this.nameField, this.memberOf});

  final SymbolKind kind;

  /// The field carrying the symbol's name (e.g. `name`); required for
  /// sym/member kinds, null for the file kind (name comes from the path).
  final String? nameField;

  /// Member attachment mode for member kinds:
  /// - `'file'` — top-level: nearest mapped ancestor, else the file node;
  /// - `'parent'` — require a nearest mapped ancestor (named error if none);
  /// - `'ancestor:<Type>'` — nearest ancestor of grammar type `<Type>`
  ///   (attachment resolved at that ancestor, named error if never found).
  final String? memberOf;
}

/// The validated mapping table (per language, DATA).
class GrammarMapping {
  GrammarMapping._(this.table);

  /// Validates [table] at load:
  /// - a file-kind entry must carry no nameField/memberOf;
  /// - sym/member entries must declare a non-empty nameField;
  /// - member entries must declare a legal memberOf mode;
  /// - `memberOf` chains must be ACYCLIC (`ancestor:A` → A is
  ///   `ancestor:B` → B is `ancestor:A` = a named load error).
  ///
  /// Unknown node types appearing in FIXTURES are caught by the
  /// conformance battery (fixture_annotation.dart), not here — the table
  /// cannot know the grammar's vocabulary at load time.
  factory GrammarMapping.validate(Map<String, GrammarNodeSpec> table) {
    if (table.isEmpty) {
      throw const GrammarMapException('empty_mapping_table');
    }
    for (final entry in table.entries) {
      final type = entry.key;
      final spec = entry.value;
      switch (spec.kind) {
        case SymbolKind.file:
          if (spec.nameField != null || spec.memberOf != null) {
            throw GrammarMapException(
              'file_kind_with_attachments:$type',
              detail:
                  'the file kind takes no nameField/memberOf '
                  '(the name comes from the path)',
            );
          }
        case SymbolKind.sym || SymbolKind.member:
          if (spec.nameField == null || spec.nameField!.isEmpty) {
            throw GrammarMapException(
              'missing_name_field:$type',
              detail: 'sym/member entries must declare a nameField',
            );
          }
          final memberOf = spec.memberOf;
          if (spec.kind == SymbolKind.member &&
              (memberOf == null ||
                  !(memberOf == 'file' ||
                      memberOf == 'parent' ||
                      memberOf.startsWith('ancestor:')))) {
            throw GrammarMapException(
              'illegal_member_of:$type',
              detail: 'memberOf must be "file", "parent" or "ancestor:<Type>"',
            );
          }
      }
    }
    _assertAcyclic(table);
    return GrammarMapping._(Map.unmodifiable(table));
  }

  /// memberOf cycle detection: follow `ancestor:<Type>` chains over the
  /// TABLE (spec-to-spec), never over parsed nodes.
  static void _assertAcyclic(Map<String, GrammarNodeSpec> table) {
    String? ancestorRef(String type) {
      final memberOf = table[type]?.memberOf;
      if (memberOf != null && memberOf.startsWith('ancestor:')) {
        return memberOf.substring('ancestor:'.length);
      }
      return null;
    }

    for (final start in table.keys) {
      final visited = <String>{start};
      var next = ancestorRef(start);
      while (next != null) {
        if (!visited.add(next)) {
          throw GrammarMapException(
            'member_of_cycle:$start',
            detail:
                'ancestor chain revisits $next — the attachment '
                'resolution could never terminate',
          );
        }
        next = ancestorRef(next);
      }
    }
  }

  final Map<String, GrammarNodeSpec> table;
}

/// One mapped symbol — the shape the workspace ETL turns into
/// MappedNodes/sub-nodes (node facts + span props; ADR 0035 §8 diagram).
class MappedSymbol {
  const MappedSymbol({
    required this.kind,
    required this.name,
    required this.grammarType,
    required this.parentName,
    required this.startByte,
    required this.endByte,
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  final SymbolKind kind;
  final String name;
  final String grammarType;

  /// Resolved attachment: the mapped parent symbol's name, or null for
  /// top-level symbols attached to the file (and for the file symbol).
  final String? parentName;

  // UTF-8 byte offsets (meaning-tree span-prop currency — see README).
  final int startByte;
  final int endByte;
  // Zero-based points (row; column in bytes, as tree-sitter yields).
  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  @override
  String toString() =>
      'MappedSymbol($kind $grammarType $name'
      '${parentName == null ? '' : ' <- $parentName'}, '
      'bytes $startByte..$endByte)';
}

/// The named runtime mapping errors (never silent).
final class GrammarMapException implements Exception {
  const GrammarMapException(this.code, {this.detail});

  /// machine-named code, e.g. `unresolved_name_field:<Type>`.
  final String code;
  final String? detail;

  @override
  String toString() =>
      'grammar_map_error($code)${detail == null ? '' : ': $detail'}';
}

/// The generic walker: ONE implementation, per-language tables.
class GrammarMapper {
  GrammarMapper({required this.mapping});

  /// The validated mapping table this walker interprets.
  final GrammarMapping mapping;

  /// Maps a parsed [root] over [source] into [MappedSymbol]s.
  ///
  /// The walker recurses depth-first; every node whose grammar type is a
  /// mapping-table key becomes a symbol. Name resolution: the node's
  /// [GrammarNodeSpec.nameField] child (tree-sitter field lookup or the
  /// first named child carrying that field — e.g. `variable_declarator`
  /// under `lexical_declaration`); unresolved → NAMED error.
  List<MappedSymbol> map(
    SourceNode root,
    String source, {
    Utf8Utf16SpanBridge? bridge,
    String? fileName,
  }) {
    final textOf =
        bridge?.text ??
        (SourceNode n) => utf8Slice(source, n.startByte, n.endByte);
    final symbols = <MappedSymbol>[];
    final fileStack = <MappedSymbol>[]; // mapped ancestors (file kind last)
    _walk(root, textOf, symbols, fileStack, fileName);
    return symbols;
  }

  void _walk(
    SourceNode node,
    String Function(SourceNode) textOf,
    List<MappedSymbol> symbols,
    List<MappedSymbol> ancestorStack,
    String? fileName,
  ) {
    final spec = mapping.table[node.type];
    MappedSymbol? mapped;
    if (spec != null) {
      mapped = switch (spec.kind) {
        SymbolKind.file => _mapFile(node, fileName),
        SymbolKind.sym ||
        SymbolKind.member => _mapSymbol(node, spec, textOf, ancestorStack),
      };
      if (mapped != null) symbols.add(mapped);
    }
    if (mapped != null) ancestorStack.add(mapped);
    for (final child in node.children) {
      _walk(child, textOf, symbols, ancestorStack, fileName);
    }
    if (mapped != null) {
      ancestorStack.removeLast();
    }
  }

  MappedSymbol? _mapFile(SourceNode node, String? fileName) => MappedSymbol(
    kind: SymbolKind.file,
    name: fileName ?? node.type,
    grammarType: node.type,
    parentName: null,
    startByte: node.startByte,
    endByte: node.endByte,
    startRow: node.startRow,
    startColumn: node.startColumn,
    endRow: node.endRow,
    endColumn: node.endColumn,
  );

  MappedSymbol? _mapSymbol(
    SourceNode node,
    GrammarNodeSpec spec,
    String Function(SourceNode) textOf,
    List<MappedSymbol> ancestorStack,
  ) {
    final nameNode =
        node.childByField(spec.nameField!) ??
        _descendantByField(node, spec.nameField!);
    if (nameNode == null) {
      throw GrammarMapException(
        'unresolved_name_field:${node.type}',
        detail:
            'no child carries field "${spec.nameField}" at bytes '
            '${node.startByte}..${node.endByte}',
      );
    }
    final parentName = spec.kind == SymbolKind.member
        ? _resolveParent(node, spec, ancestorStack)
        : null;
    return MappedSymbol(
      kind: spec.kind,
      name: textOf(nameNode),
      grammarType: node.type,
      parentName: parentName,
      startByte: node.startByte,
      endByte: node.endByte,
      startRow: node.startRow,
      startColumn: node.startColumn,
      endRow: node.endRow,
      endColumn: node.endColumn,
    );
  }

  /// Attachment resolution (see [GrammarNodeSpec.memberOf]).
  String? _resolveParent(
    SourceNode node,
    GrammarNodeSpec spec,
    List<MappedSymbol> ancestorStack,
  ) {
    final memberOf = spec.memberOf!;
    if (memberOf == 'file') {
      // Top-level: the nearest NON-file mapped ancestor declares this
      // member; none → attached to the file node itself (parentName null).
      for (final ancestor in ancestorStack.reversed) {
        if (ancestor.kind != SymbolKind.file) return ancestor.name;
      }
      return null;
    }
    if (memberOf == 'parent') {
      // The nearest mapped NON-file ancestor declares this member; the
      // file node itself is not a parent (a top-level method has none).
      for (final ancestor in ancestorStack.reversed) {
        if (ancestor.kind != SymbolKind.file) return ancestor.name;
      }
      throw GrammarMapException(
        'unresolved_member_parent:${node.type}',
        detail:
            'memberOf "parent" but no mapped ancestor declares this '
            'node (only the file node encloses it)',
      );
    }
    // ancestor:<Type> — walk the parsed ANCESTOR chain to the nearest node
    // of the named grammar type, then attach to the nearest mapped symbol
    // found walking the same path (the type itself when it is mapped).
    final targetType = memberOf.substring('ancestor:'.length);
    if (!mapping.table.containsKey(targetType)) {
      throw GrammarMapException(
        'unknown_ancestor_type:${node.type}',
        detail:
            'memberOf "$memberOf" references a node type that is not a '
            'mapping-table key',
      );
    }
    var sawTarget = false;
    for (final ancestor in ancestorStack.reversed) {
      if (ancestor.grammarType == targetType) sawTarget = true;
      if (sawTarget) return ancestor.name;
    }
    throw GrammarMapException(
      'unresolved_ancestor:${node.type}',
      detail:
          'no ancestor of type "$targetType" encloses this node '
          '(memberOf "$memberOf")',
    );
  }

  /// Fallback name resolution: first DESCENDANT (depth ≤ 2) carrying the
  /// field — covers `lexical_declaration`/`variable_declaration`, whose
  /// `name` field lives on their `variable_declarator` child.
  SourceNode? _descendantByField(SourceNode node, String field) {
    for (final child in node.children) {
      final direct = child.childByField(field);
      if (direct != null) return direct;
    }
    return null;
  }
}

/// Slices [source] (a Dart UTF-16 string) by UTF-8 byte offsets — the
/// mapper's no-bridge fallback. Bridge-backed mapping is preferred (the
/// tested path); this helper exists so the mapper stays usable standalone.
String utf8Slice(String source, int startByte, int endByte) {
  final bytes = utf8.encode(source);
  return utf8.decode(bytes.sublist(startByte, endByte), allowMalformed: true);
}
