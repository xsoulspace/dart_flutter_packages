# xsoulspace_treesitter_raw

ADR 0035 §8 leaf package: the tree-sitter spike. A `SourceParser` FFI
implementation over the tree-sitter C API, the UTF-8 → UTF-16 span bridge,
the generic `GrammarMapper` interpreter, and the `ParserConformance`
battery — in ONE leaf, so the workspace never hard-depends on the FFI.

**Dependency law**: this package imports `dart:ffi`, `ffi`,
`source_span` and NOTHING else from the repo. Zero imports of
`xsoulspace_agentic_workspace` / `xsoulspace_agentic_harness` / `ecsly`.
The workspace consumes the pure-Dart `SourceParser` seam; where the dylib
does not build, the mechanical scanner serves and the conformance suite
still runs.

## Unit discipline (PINNED — read before touching spans)

- tree-sitter yields **UTF-8 BYTE offsets** (`ts_node_start_byte`,
  `ts_node_end_byte`) and points whose columns are BYTE columns.
- Dart strings are **UTF-16 code-unit** sequences; `package:source_span`
  works in code units.
- The meaning tree's `span_start` / `span_end` props stay in **UTF-8
  byte offsets** (the fs span reader seeks the file in bytes) —
  tree-sitter offsets plug in DIRECTLY on that path.
- The **ONLY** sanctioned byte → code-unit conversion is
  `Utf8Utf16SpanBridge` (`lib/src/span_bridge.dart`), covered by
  multibyte golden tests (emoji = 4 bytes / 2 code units; CJK = 3 bytes /
  1 code unit). Never index a Dart string with a byte offset; never seek
  a file with a code-unit offset. This is the classic silent corruption —
  the tests exist to make it loud.

## Building the grammar dylib

```bash
tool/build_grammar.sh
```

Shallow-clones tree-sitter (`v0.25.8`) and tree-sitter-typescript
(`v0.23.2`, both PINNED — bumping a pin requires re-running the
conformance battery) into `.grammar-src/`, and compiles
`parser.c` + `scanner.c` + the runtime's `lib.c` into
`.dylibs/libtree_sitter_typescript.{dylib,so}`. macOS/Linux first (ADR
0035 §8 non-goal: no wasm, no windows dylib until the native path proves
on the dev platform). Override the search with `XS_TREESITTER_DYLIB`.

## Layout

- `lib/src/source_parser.dart` — THE SEAM (pure Dart): `SourceParser`,
  `SourceNode` `{type, field children, byte offsets, point}`.
- `lib/src/tree_sitter_bindings.dart` — raw C API bindings (the only
  `dart:ffi` file).
- `lib/src/tree_sitter_parser.dart` — the FFI `SourceParser`; the C tree
  is materialized and freed before `parse` returns (no handle leaks).
- `lib/src/span_bridge.dart` — the span bridge (above).
- `lib/src/grammar_mapper.dart` — ONE generic walker driven by a node-kind
  mapping table `{grammarNodeType: {kind: sym|member|file, nameField,
  memberOf: file|parent|ancestor:<Type>}}`; validated at load (unknown
  ancestor types, unresolved name fields, `memberOf` cycles = NAMED
  errors).
- `lib/src/ts_mapping_table.dart` — the TypeScript table (member symbols
  day one: methods/functions/arrows/consts as `member` nodes under their
  declaring parent, so `replace_member_body` has a node to address).
- `lib/src/fixture_annotation.dart` — fixture `// @map` markers: node
  expectations are DERIVED from the fixtures (ADR 0022 invariant — no
  hand-authored parallel truth table). Unknown node types in fixtures are
  named errors.
- `lib/src/parser_conformance.dart` — the battery ANY `SourceParser` must
  pass; the scanner↔tree-sitter delta report is the future clause-1
  evidence, measured as data.
- `lib/src/budget_proof.dart` — the clause-4 graduated-profile check
  (1,424 chars/4 → cutBudget 628; the sample cut must fit).

## Scope notes (honest)

- **No query engine in the spike** (ADR 0035 §8): field-based extraction
  (nameField + memberOf) covers the symbol map. A query engine lands only
  if a measured row pulls captures (e.g. refs edges — a declared escape).
- **No mechanical TS scanner here yet**: the battery is built for it; the
  delta table fills when the scanner family lands.
