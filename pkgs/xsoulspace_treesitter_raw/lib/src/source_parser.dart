// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 — THE SEAM (pure Dart): a source-code parser returns a tree
/// of nodes with `{type, field children, byte offsets, point (row/col)}`.
///
/// Two implementations exist or are planned:
/// - `TreeSitterParser` (this package) — FFI over the tree-sitter C API;
/// - the future v1 mechanical TS scanner (pure Dart, dependency-light).
///
/// The `ParserConformance` battery (parser_conformance.dart) runs against
/// ANY implementation, so the scanner↔tree-sitter conformance DELTA becomes
/// the ADR 0035 §7 clause-1 evidence, measured as data — never argued.
///
/// UNIT DISCIPLINE (pinned in the package README): offsets are UTF-8 BYTE
/// offsets (tree-sitter's native currency and the meaning-tree `span_*`
/// prop currency); the ONLY sanctioned conversion to UTF-16 Dart code-unit
/// offsets lives in `span_bridge.dart`.
library;

/// One node of a parsed source tree (pure Dart — no ffi, no grammar).
///
/// `children` carries the node's NAMED children in source order, each
/// annotated with the [field] under which its parent references it (null
/// when the parent has no field for it). Unnamed (punctuation) nodes are
/// omitted — the mapper and conformance battery are field/named based.
class SourceNode {
  const SourceNode({
    required this.type,
    required this.field,
    required this.startByte,
    required this.endByte,
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
    required this.children,
  });

  /// The grammar node type (`ts_node_type`) — e.g. `class_declaration`.
  final String type;

  /// The field name under which this node appears in its PARENT
  /// (e.g. `body`, `name`); null for the root or unnamed positions.
  final String? field;

  /// UTF-8 byte offsets (tree-sitter currency — see the unit discipline).
  final int startByte;
  final int endByte;

  /// Zero-based (row, column) points; column in UTF-8 BYTE units as
  /// tree-sitter yields them.
  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  /// Named children in source order (unnamed punctuation omitted).
  final List<SourceNode> children;

  /// First named child under [field], or null.
  SourceNode? childByField(String name) {
    for (final c in children) {
      if (c.field == name) return c;
    }
    return null;
  }

  /// Depth-first pre-order walk (self first).
  Iterable<SourceNode> walk() sync* {
    yield this;
    for (final c in children) {
      yield* c.walk();
    }
  }

  @override
  String toString() =>
      'SourceNode($type, bytes $startByte..$endByte, '
      'pt $startRow:$startColumn..$endRow:$endColumn, '
      '${children.length} children)';
}

/// ADR 0035 §8 — the parser seam: ANY implementation (FFI or mechanical
/// scanner) implements exactly this. Deterministic: the same source yields
/// the same tree.
abstract interface class SourceParser {
  /// Parses [source] and returns the materialized pure-Dart tree (the C
  /// tree, if any, is released before returning — no native handle leaks
  /// into the result).
  SourceNode parse(String source);

  /// Releases implementation resources (FFI: parser). Idempotent.
  void dispose();
}
