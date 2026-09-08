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

## Scanner↔tree-sitter delta (2026-09-08)

The v1 mechanical TS scanner landed (ADR 0035 §6 Tier C v1:
`xsoulspace_agentic_workspace/lib/src/ts_materializer.dart`, registered as
the `ts` binding). The battery ran BOTH ways the ADR demanded: the 4
annotated fixtures (`calculator.ts`, `functions.ts`, `generics.ts`,
`multibyte.ts`) went through the scanner's map fn (`tsScanSymbols`) with
the expected-node derivation REPLICATED as test data from the `// @map`
marker grammar (the workspace may not import the FFI leaf — §8 layering).
Kind/name/memberOf compared as multisets; spans verified byte-precise
(the UTF-8 slice at the span offsets must be the declaration, emoji/CJK
included).

| Fixture | Scanner nodes | tree-sitter (marker-derived) | Delta | Named class |
| --- | --- | --- | --- | --- |
| calculator.ts | 5 (1 sym + 4 member, incl. member arrow const; decorator skipped) | 5 | 0 | none |
| functions.ts | 4 (2 sym + 2 member: arrow consts as lexical_declaration) | 4 | 0 | none |
| generics.ts | 6 (2 sym + 4 member: property_signature/method_signature included) | 6 | 0 | none |
| multibyte.ts | 3 (1 sym + 2 member; function-local const 縮める.ラベル included) | 3 | 0 | none |

**Final delta: ZERO** — the scanner matches the FFI-derived expectations
on every fixture, spans byte-precise over emoji/CJK.

### Named scanner failure classes found and repaired BEFORE landing

These were caught by the conformance battery + the byte-precision gate
during landing (integration-test evidence, NOT real task rows — the §7
clause-1 gate still needs REAL bounces attributed to extractor
insufficiency; state that honestly):

- `mask_buffer_all_inert` — `_maskContent` wrote its masked output into a
  space-filled buffer without copying unmasked characters: EVERY character
  was inert, the scanner returned zero nodes everywhere. Caught by the
  first ts test run (the §7 "scanner returns nothing" shape would have
  been a total map outage).
- `function_body_members_unindexed` — the var-decl branch (function-local
  consts are member nodes under the nearest mapped ancestor) sat behind an
  `atTopLevel || atContainerMember` guard, so `const ラベル` inside
  `縮める` was never reached. Caught by the multibyte fixture (the ONLY
  fixture exercising the shape — fixture-first evidence working as
  designed).
- `span_boundary_parse_ambiguous` — the `tsym_<fileNodeId>_<idTail>`
  anchor's file/tail boundary was parsed at the FIRST underscore, but the
  file id itself is path-flattened (`f_src_pets.ts`) — every nested-path
  edit bounced `file_not_found: src`. Fixed by resolving the boundary
  against the files the jail actually scans (longest file-id prefix) and
  deriving the tail from the RESOLVED path.

### Honest scope notes

- The delta compares node KINDS/NAMES/memberOf + span byte-precision, not
  grammar-node identity: tree-sitter starts a declaration's span at the
  declaration keyword, the scanner spans include `export`/modifiers. The
  markers carry no spans, so this is an OBSERVATION, not a measured
  mismatch; it matters only if a consumer ever needs the export-modifier
  boundary (none today — the splice fences on the member span).
- §7 clause status after this landing: clauses 1–2 remain **OPEN** (the
  three classes above are integration-fixture evidence, not measured task
  bounces); clause 3 advances from PRE-SEEDED to **half-proven** (the
  scanner half now runs the same battery; the FFI half was already green
  — the full cross-implementation run in one process still needs the
  dylib+scanner in one suite).

## C# scanner baseline (2026-09-08)

The v1 mechanical C# scanner landed (ADR 0035 §6 Tier C v1, the second
full-code non-Dart family:
`xsoulspace_agentic_workspace/lib/src/cs_materializer.dart`, registered as
the `cs` binding — actions `insert_member`/`remove_member`/
`apply_executable` ONLY; `replace_member_body` is deliberately OMITTED,
the v1 limitation IS registry data). The battery ran the same way the ts
landing did: the 2 annotated fixtures (`Kennel.cs`, `Shapes.cs`) through
the scanner's map fn (`csScanSymbols`) with the expected-node derivation
REPLICATED as test data from the `// @map` marker grammar
(`test/cs_materializer_test.dart` — the workspace may not import the FFI
leaf, §8 layering). Kind/name/memberOf compared as multisets; spans
verified byte-precise (the UTF-8 slice at the span offsets must be the
declaration; member spans ABSORB the immediately preceding contiguous
attribute lines — no phantom attribute nodes). A third golden fixture
(multibyte: CJK identifiers, emoji in comments/strings) asserts the
byte-offset span bridge decodes exactly.

| Fixture | Scanner nodes | tree-sitter (marker-derived) | Delta | Named class |
| --- | --- | --- | --- | --- |
| Kennel.cs | 5 (2 sym: file_scoped_namespace_declaration Kennel, class_declaration Dog; 3 member: field/property/method, `[Fact]` rides the method span) | not built — grammar pending | 0 (vs markers) | none |
| Shapes.cs | 8 (5 sym: block namespace_declaration Geometry, interface IShape, struct Point, enum Kind, class Square; 3 member: IShape.Area, Point.X, Square.Area; enum members not indexed — v1 scope) | not built — grammar pending | 0 (vs markers) | none |

**Final delta: ZERO** against the marker-derived expectations on both
fixtures, spans byte-precise over CJK/emoji. The tree-sitter-c-sharp
column is **not built — grammar pending**: the baseline pins the scanner
to the tree-sitter-c-sharp NODE-KIND VOCABULARY (the same kind strings
the markers carry) so the conformance delta becomes measurable as data
the day an FFI mapper lands (ADR 0035 §8 item 5) — today only the
marker-derived half of the battery runs.

### Named scanner failure classes found and repaired BEFORE landing

Caught by the first probe runs of the conformance battery + the
byte-precision gate during landing (integration-test evidence, NOT real
task rows):

- `unicode_property_regex_unflagged` — the declaration regexes
  (`_nsRe`, `_classRe`, `_interfaceRe`, `_structRe`, `_enumRe`,
  `_recordRe`, `_modifiersRe`, `_ctorRe`) used `\p{L}` Unicode property
  escapes WITHOUT Dart's `unicode: true` flag, where they silently match
  nothing: the scanner returned ZERO nodes on every input (the §7
  "scanner returns nothing" total-map-outage shape, again caught before
  landing). The member regexes (`_methodRe`, `_propertyRe`, `_fieldRe`)
  had the flag; the fix adds it uniformly.
- `block_namespace_declarations_unindexed` — the declaration branch
  fired only at brace depth 0 or inside a container-kind body, so
  declarations inside a block-scoped `namespace X { }` (depth 1, and the
  namespace is NOT a container kind) were never indexed. Caught by the
  Shapes.cs fixture (the ONLY fixture exercising the block-scoped form —
  fixture-first evidence working as designed). Fixed by a namespace-
  scope depth guard; namespaces stay OUT of the container kinds, so
  `insert_member` still targets declaring TYPE bodies only (the
  namespace node itself is not an insert target — the §6 brief
  contract).

### Honest scope notes

- The delta compares node KINDS/NAMES/memberOf + span byte-precision,
  not grammar-node identity: member spans include access modifiers and
  ride attributes (tree-sitter starts at the attribute/keyword boundary
  differently) — an OBSERVATION, not a measured mismatch; the splice
  fences on the member span, so the boundary choice is safe.
- v1 scanner omissions (honest, never wrong spans): delegates, operator
  overloads, indexers, local functions, enum members, and
  multi-declarator fields past the first declarator are not indexed;
  interpolated-string holes are masked whole (braces inside holes never
  count as structure).
- The `dotnet_build` oracle is graded by a FAKE jail-local `.dotnet/dotnet`
  in the tests (the mirror of the ts jail's fake `tsc`); a real SDK run
  is not exercised on this runner (dotnet absent from PATH — the
  `oracle_unavailable` precondition test runs for real here, the
  `cs_error` auto-revert runs against the fake's exit code).
