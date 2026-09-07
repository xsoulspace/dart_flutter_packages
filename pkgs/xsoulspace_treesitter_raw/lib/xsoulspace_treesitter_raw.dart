/// xsoulspace_treesitter_raw — ADR 0035 §8 leaf package (the ONLY dart:ffi
/// import in the tree-sitter spike; ZERO imports of
/// xsoulspace_agentic_workspace / agentic_harness / ecsly).
///
/// Exports:
/// - `SourceParser` / `SourceNode` — the pure-Dart seam (parser_conformance
///   runs against ANY implementation);
/// - `TreeSitterParser` — the FFI implementation (pinned grammar revision,
///   tool/build_grammar.sh builds the dylib);
/// - `Utf8Utf16SpanBridge` — the ONE tested UTF-8 byte ↔ UTF-16 code-unit
///   conversion (multibyte golden tests mandatory);
/// - `GrammarMapper` + the TS mapping table — ONE generic walker, tables
///   as data (member symbols day one);
/// - `ParserConformance` — the battery for the scanner↔tree-sitter delta
///   (the future clause-1 evidence);
/// - `budget_proof` — the clause-4 graduated-profile check.
library;

export 'src/budget_proof.dart';
export 'src/dylib_loader.dart';
export 'src/fixture_annotation.dart';
export 'src/grammar_mapper.dart';
export 'src/parser_conformance.dart';
export 'src/source_parser.dart';
export 'src/span_bridge.dart';
export 'src/tree_sitter_parser.dart';
export 'src/ts_mapping_table.dart';
