// ignore_for_file: lines_longer_as_80_chars, non_constant_identifier_names

/// Raw tree-sitter C API bindings (ADR 0035 §8 item 1) — the ONLY dart:ffi
/// usage in the spike. Loaded from ONE dylib that contains BOTH the
/// tree-sitter runtime and the compiled grammar (tool/build_grammar.sh
/// compiles parser.c + scanner.c + the runtime's lib.c together).
///
/// API surface used (the minimal walk set): ts_parser_new /
/// ts_parser_set_language / ts_parser_parse_string / ts_parser_delete,
/// ts_tree_root_node / ts_tree_delete, and the ts_node_* walk:
/// child_count, child, is_named, field_name_for_child, named_child_count,
/// named_child, child_by_field_name, start_byte, end_byte, start_point,
/// end_point, symbol, type.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// tree-sitter `TSNode` — returned BY VALUE; layout per api.h v0.25.8:
/// `{ uint32_t context[4]; const void *id; const TSTree *tree; }`.
final class TsNode extends Struct {
  @Array(4)
  external Array<Uint32> context;

  external Pointer<Void> id;

  external Pointer<Void> tree;

  /// A null TSNode (no such child/field) has id == nullptr.
  bool get isNull => id == nullptr;
}

/// tree-sitter `TSPoint` — `{ uint32_t row; uint32_t column; }`.
final class TsPoint extends Struct {
  @Uint32()
  external int row;

  @Uint32()
  external int column;
}

/// The bound C functions over one opened [DynamicLibrary].
class TsApi {
  TsApi._(DynamicLibrary lib)
    : ts_parser_new = lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'ts_parser_new',
          ),
      ts_parser_delete = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('ts_parser_delete'),
      ts_parser_set_language = lib
          .lookupFunction<
            Bool Function(Pointer<Void>, Pointer<Void>),
            bool Function(Pointer<Void>, Pointer<Void>)
          >('ts_parser_set_language'),
      ts_parser_parse_string = lib
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Uint8>,
              Uint32,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Uint8>,
              int,
            )
          >('ts_parser_parse_string'),
      ts_tree_root_node = lib
          .lookupFunction<
            TsNode Function(Pointer<Void>),
            TsNode Function(Pointer<Void>)
          >('ts_tree_root_node'),
      ts_tree_delete = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('ts_tree_delete'),
      ts_node_type = lib
          .lookupFunction<
            Pointer<Utf8> Function(TsNode),
            Pointer<Utf8> Function(TsNode)
          >('ts_node_type'),
      ts_node_symbol = lib
          .lookupFunction<Uint16 Function(TsNode), int Function(TsNode)>(
            'ts_node_symbol',
          ),
      ts_node_start_byte = lib
          .lookupFunction<Uint32 Function(TsNode), int Function(TsNode)>(
            'ts_node_start_byte',
          ),
      ts_node_end_byte = lib
          .lookupFunction<Uint32 Function(TsNode), int Function(TsNode)>(
            'ts_node_end_byte',
          ),
      ts_node_start_point = lib
          .lookupFunction<TsPoint Function(TsNode), TsPoint Function(TsNode)>(
            'ts_node_start_point',
          ),
      ts_node_end_point = lib
          .lookupFunction<TsPoint Function(TsNode), TsPoint Function(TsNode)>(
            'ts_node_end_point',
          ),
      ts_node_child_count = lib
          .lookupFunction<Uint32 Function(TsNode), int Function(TsNode)>(
            'ts_node_child_count',
          ),
      ts_node_child = lib
          .lookupFunction<
            TsNode Function(TsNode, Uint32),
            TsNode Function(TsNode, int)
          >('ts_node_child'),
      ts_node_is_named = lib
          .lookupFunction<Bool Function(TsNode), bool Function(TsNode)>(
            'ts_node_is_named',
          ),
      ts_node_field_name_for_child = lib
          .lookupFunction<
            Pointer<Utf8> Function(TsNode, Uint32),
            Pointer<Utf8> Function(TsNode, int)
          >('ts_node_field_name_for_child'),
      ts_node_named_child_count = lib
          .lookupFunction<Uint32 Function(TsNode), int Function(TsNode)>(
            'ts_node_named_child_count',
          ),
      ts_node_named_child = lib
          .lookupFunction<
            TsNode Function(TsNode, Uint32),
            TsNode Function(TsNode, int)
          >('ts_node_named_child'),
      ts_node_child_by_field_name = lib
          .lookupFunction<
            TsNode Function(TsNode, Pointer<Utf8>, Uint32),
            TsNode Function(TsNode, Pointer<Utf8>, int)
          >('ts_node_child_by_field_name');

  /// Opens [dylibPath] and binds the C API; [languageSymbol] is the
  /// grammar's exported entry point (e.g. `tree_sitter_typescript`).
  factory TsApi.open(String dylibPath, String languageSymbol) {
    final lib = DynamicLibrary.open(dylibPath);
    final api = TsApi._(lib);
    final language = lib
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          languageSymbol,
        )();
    if (language == nullptr) {
      throw StateError(
        'tree-sitter: language symbol "$languageSymbol" resolved to null in '
        '$dylibPath (grammar dylib built without the language?)',
      );
    }
    api._language = language;
    return api;
  }

  late final Pointer<Void> _language;

  final Pointer<Void> Function() ts_parser_new;
  final void Function(Pointer<Void>) ts_parser_delete;
  final bool Function(Pointer<Void>, Pointer<Void>) ts_parser_set_language;
  final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Uint8>,
    int,
  )
  ts_parser_parse_string;
  final TsNode Function(Pointer<Void>) ts_tree_root_node;
  final void Function(Pointer<Void>) ts_tree_delete;
  final Pointer<Utf8> Function(TsNode) ts_node_type;
  final int Function(TsNode) ts_node_symbol;
  final int Function(TsNode) ts_node_start_byte;
  final int Function(TsNode) ts_node_end_byte;
  final TsPoint Function(TsNode) ts_node_start_point;
  final TsPoint Function(TsNode) ts_node_end_point;
  final int Function(TsNode) ts_node_child_count;
  final TsNode Function(TsNode, int) ts_node_child;
  final bool Function(TsNode) ts_node_is_named;
  final Pointer<Utf8> Function(TsNode, int) ts_node_field_name_for_child;
  final int Function(TsNode) ts_node_named_child_count;
  final TsNode Function(TsNode, int) ts_node_named_child;
  final TsNode Function(TsNode, Pointer<Utf8>, int) ts_node_child_by_field_name;

  /// One live parser with the language set; throws on failure.
  Pointer<Void> newParser() {
    final parser = ts_parser_new();
    if (parser == nullptr) {
      throw StateError('tree-sitter: ts_parser_new returned null');
    }
    if (!ts_parser_set_language(parser, _language)) {
      ts_parser_delete(parser);
      throw StateError(
        'tree-sitter: ts_parser_set_language failed (grammar ABI mismatch '
        'with the runtime compiled into the dylib?)',
      );
    }
    return parser;
  }

  String typeOf(TsNode node) => ts_node_type(node).toDartString();

  /// Field name of [childIndex] under [parent], or null when unnamed.
  String? fieldNameForChild(TsNode parent, int childIndex) {
    final p = ts_node_field_name_for_child(parent, childIndex);
    if (p == nullptr) return null;
    final s = p.toDartString();
    return s.isEmpty ? null : s;
  }

  /// Parses [utf8Source] (already UTF-8 encoded); returns the tree handle
  /// or throws on failure. Caller owns the tree (ts_tree_delete).
  Pointer<Void> parseString(Pointer<Void> parser, Uint8List utf8Source) {
    final buf = calloc<Uint8>(utf8Source.length);
    try {
      buf.asTypedList(utf8Source.length).setAll(0, utf8Source);
      final tree = ts_parser_parse_string(
        parser,
        nullptr,
        buf,
        utf8Source.length,
      );
      if (tree == nullptr) {
        throw StateError(
          'tree-sitter: ts_parser_parse_string returned a null tree',
        );
      }
      return tree;
    } finally {
      calloc.free(buf);
    }
  }
}

/// UTF-8 encode helper kept next to the FFI layer (byte discipline).
Uint8List utf8Bytes(String source) => utf8.encode(source);
