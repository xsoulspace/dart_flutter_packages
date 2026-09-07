// ignore_for_file: lines_longer_as_80_chars

# results_etl_grammar — tree-sitter spike (ADR 0035 §8, clause-3/4 pre-seed)

Date: 2026-09-08. ADR: [0035](../../../../docs/decisions/0035_materializer_bindings_language_families.md)
§7 (four-clause gate) + §8 (spike scope). Deliverable: ONE new leaf
package, [pkgs/xsoulspace_treesitter_raw](../../../xsoulspace_treesitter_raw/)
— the ONLY `dart:ffi` import in the step; ZERO imports of
xsoulspace_agentic_workspace / xsoulspace_agentic_harness / ecsly. No
existing package, PLAN, or ADR was modified. Not committed.

## What landed (ADR 0035 §8 items 1–7)

| Item | Status | Notes |
| --- | --- | --- |
| 1. `SourceParser` interface | LANDED | pure Dart: `parse(source)` → `SourceNode` tree `{type, field children, UTF-8 byte offsets, point (row/col)}` — the SEAM |
| 2. FFI impl over the tree-sitter C API | LANDED | `ts_parser_new/set_language/parse_string/delete`, `ts_tree_root_node/delete`, walk via `ts_node_*` (child/is_named/field_name_for_child/named_child/child_by_field_name/start_byte/end_byte/start_point/end_point/symbol/type); grammar loaded from ONE dylib containing runtime + grammar (`DynamicLibrary.open`); C tree materialized and FREED before `parse` returns; 200-parse + 20-parser-lifecycle leak cycle test; `dispose` idempotent, use-after-dispose = named Dart error |
| 3. `tool/build_grammar.sh` | LANDED + EXECUTED | pinned revisions: tree-sitter `v0.25.8`, tree-sitter-typescript `v0.23.2` (shallow clones, cache-dir cached); `cc -shared -fPIC parser.c scanner.c lib.c` → `.dylibs/libtree_sitter_typescript.dylib`; macOS built GREEN (Apple clang, arm64); Linux path in the script, untested here |
| 4. Span bridge | LANDED | UTF-8 byte ↔ UTF-16 code-unit conversion, ONE implementation (`Utf8Utf16SpanBridge`), 11 multibyte golden tests (emoji 4-byte/2-unit, CJK 3-byte/1-unit) + a NEGATIVE PROOF test (naive byte-as-code-unit slicing demonstrably corrupts — the test would catch a regression). Unit discipline pinned in the package README |
| 5. `GrammarMapper` | LANDED | ONE generic walker over a node-kind TABLE (data) `{grammarNodeType: {kind: sym\|member\|file, nameField, memberOf: file\|parent\|ancestor:<Type>}}`; load-time validation (illegal memberOf, missing nameField, file-kind attachments, `memberOf` cycles = named errors); runtime named errors (`unresolved_name_field`, `unresolved_member_parent`, `unknown_ancestor_type`, `unresolved_ancestor`); 14 mapper tests (pure Dart) |
| 6. TS table + fixtures | LANDED | 16-entry TypeScript mapping table, member symbols included from day one (method_definition, method_signature, property_signature, public_field_definition/field_definition, lexical/variable_declaration — arrow consts via declarator name resolution); 4 annotated fixtures (class+decorator+members, top-level functions+arrow consts+generator, generics+interface signatures, emoji/CJK identifiers); expectations DERIVED from `// @map` fixture markers, held BOTH directions (missing AND unclaimed = failure) — zero host-authored parallel truth (ADR 0022 invariant) |
| 7. `ParserConformance` battery | LANDED + RUN | implementation-agnostic (runs against ANY `SourceParser`); includes a span round-trip check per symbol (UTF-8 re-encode must equal the byte span); the delta table renders from the report. The future v1 mechanical TS scanner runs the SAME battery — that delta is the clause-1 evidence, still pending the scanner |
| 8. Budget proof | LANDED + RUN | see below |

## Conformance output (the battery vs the FFI impl)

| fixture | implementation | pass | symbols | ms | failures |
| --- | --- | --- | --- | --- | --- |
| calculator.ts | TreeSitterParser(ffi) | PASS | 6 | 9.0 | - |
| functions.ts | TreeSitterParser(ffi) | PASS | 5 | 1.0 | - |
| generics.ts | TreeSitterParser(ffi) | PASS | 7 | 0.0 | - |
| multibyte.ts | TreeSitterParser(ffi) | PASS | 4 | 0.0 | - |

All four fixtures PASS both directions (every marker satisfied; every
mapped symbol claimed). The scanner↔tree-sitter DELTA row is empty by
construction — the second implementation does not exist yet (v1 scanner
is the Tier C landing, ADR 0035 §6). Clause 1 (the ≥3 named
mechanical-scanner failure classes) CANNOT be pre-seeded by this spike:
it needs REAL task rows attributed to extractor insufficiency.

## Budget proof (clause 4 — fits=true)

Graduated profile row reproduced as data (PLAN.md / ADR 0034):
`1,424 chars / 4 → cutBudget 628` (window 984 = 628 + 356).

Sample meaning cut over `calculator.ts` mapped nodes — node-fact rows
(file + sym + 4 member facts, incl. the member arrow const) + ONE
point-cut (`Calculator.greet`'s span read through the span bridge):

- cutChars: **487**
- cutTokens: **122** (487/4)
- cutBudgetTokens: **628** → **fits: true** — the 4k AFM tier still funds
  the cut with the new node kinds (sym + member + file) included.

Honest scope of this proof: it demonstrates the CUT fits the graduated
tier; it does NOT re-measure the live registry overhead (that re-measure
is the §Consequences measurement duty when ts+c# actually REGISTER —
registry growth is data; expectation delta 0).

## Validation

`cd pkgs/xsoulspace_treesitter_raw`: `dart analyze` → **No issues found**;
test suite → **35 tests, all pass** (flutter route — `dart test` fails at
the WORKSPACE resolution level because the monorepo workspace requires
the Flutter SDK; the package itself is pure Dart + ffi/source_span and
`flutter test` runs it green). Grammar dylib built green on macOS
(arm64); NOT blocked — no blocker to record.

## Clause status (ADR 0035 §7) — HONEST

| Clause | Status after this spike |
| --- | --- |
| 1. ≥3 named mechanical-scanner failure classes | **OPEN** — needs the v1 TS scanner + REAL task bounces attributed to extractor insufficiency; this spike only built the battery that will measure the delta |
| 2. Measured workaround-cost row | **OPEN** — needs a REAL ts/c# task row (review-mode or failure) in the evidence ledger |
| 3. Grammar→meaning nodes with zero host-authored expectations | **PRE-SEEDED** — the FFI half is proven: mapping is table+fixture-derived data, validated both directions, multibyte-safe; NOT closed until the scanner half runs the same battery (the delta is the deliverable) |
| 4. Budget proof (4k tier fits) | **PRE-SEEDED** — sample cut fits=true (487 chars → 122 tokens ≤ 628); NOT the registry re-measure |

**The gate therefore stays CLOSED**: no FFI dep lands in
xsoulspace_agentic_workspace regardless (ADR 0035 §8 layering — the leaf
package is standalone; the workspace consumes only the pure-Dart
`SourceParser` seam when a measured row pulls it).

## Scope notes (recorded per the brief)

- **No query engine in the spike** — field-based extraction (nameField +
  memberOf) covers the symbol map; the tree-sitter query/captures API is
  NOT needed for the spike. It lands only if a measured row pulls
  captures (e.g. `refs` edges — a declared escape until then), behind the
  same GrammarMapper seam.
- The grammar dylib is a BUILD step (tool/build_grammar.sh), not a
  runtime dependency; where it cannot build, the mechanical scanner
  serves and the conformance suite still runs (missing dylib = a NAMED
  skip reason, never a silent fallback).
- Non-goals honored: no wasm, no grammar authoring, no windows dylib.
