// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §8 item 1 — the FFI `SourceParser` implementation over the
/// tree-sitter C API. Materializes the whole tree into the pure-Dart
/// `SourceNode` shape and releases the C tree BEFORE returning (no native
/// handle escapes into the result — the leak check is structural).
library;

import 'dart:convert';
import 'dart:ffi';

import 'dylib_loader.dart';
import 'source_parser.dart';
import 'tree_sitter_bindings.dart';

/// A grammar dylib backed `SourceParser` (tree-sitter-typescript by
/// default). Throws a NAMED error when the dylib has not been built —
/// run `tool/build_grammar.sh` (the mechanical scanner serves as the
/// graceful degradation path per ADR 0035 §8; never a silent fallback).
class TreeSitterParser implements SourceParser {
  TreeSitterParser._(this._api, this._parser, this.dylibPath);

  /// Opens the grammar dylib (search order in [findGrammarDylib]) and
  /// creates one C parser with the pinned grammar's language set.
  factory TreeSitterParser.open({
    String? dylibPath,
    String languageSymbol = 'tree_sitter_typescript',
  }) {
    final path = dylibPath ?? findGrammarDylib();
    if (path == null) {
      throw const GrammarDylibMissingException();
    }
    final api = TsApi.open(path, languageSymbol);
    final parser = api.newParser();
    return TreeSitterParser._(api, parser, path);
  }

  final TsApi _api;
  Pointer<Void> _parser;
  bool _disposed = false;

  /// The dylib this parser loaded (for the conformance report provenance).
  final String dylibPath;

  @override
  SourceNode parse(String source) {
    if (_disposed) {
      throw StateError('TreeSitterParser used after dispose()');
    }
    final tree = _api.parseString(_parser, utf8.encode(source));
    try {
      final root = _api.ts_tree_root_node(tree);
      return _materialize(root, field: null);
    } finally {
      _api.ts_tree_delete(tree);
    }
  }

  /// Recursive pure-Dart materialization of one C node (named children
  /// only, each stamped with the field its parent references it under).
  SourceNode _materialize(TsNode node, {required String? field}) {
    final childCount = _api.ts_node_child_count(node);
    final children = <SourceNode>[];
    for (var i = 0; i < childCount; i++) {
      final child = _api.ts_node_child(node, i);
      if (!_api.ts_node_is_named(child)) continue;
      final childField = _api.fieldNameForChild(node, i);
      children.add(_materialize(child, field: childField));
    }
    final start = _api.ts_node_start_point(node);
    final end = _api.ts_node_end_point(node);
    return SourceNode(
      type: _api.typeOf(node),
      field: field,
      startByte: _api.ts_node_start_byte(node),
      endByte: _api.ts_node_end_byte(node),
      startRow: start.row,
      startColumn: start.column,
      endRow: end.row,
      endColumn: end.column,
      children: children,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _api.ts_parser_delete(_parser);
  }
}

/// The named missing-dylib signal (ADR 0035 §8: the dylib is a build step,
/// not a runtime dependency — the mechanical scanner serves where it
/// cannot build; the conformance suite still runs).
final class GrammarDylibMissingException implements Exception {
  const GrammarDylibMissingException();

  @override
  String toString() =>
      'grammar_dylib_missing: run tool/build_grammar.sh to fetch the pinned '
      'grammar revision and compile the dylib (ADR 0035 §8)';
}
