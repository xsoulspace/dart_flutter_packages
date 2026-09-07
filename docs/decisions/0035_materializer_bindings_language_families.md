# ADR 0035 — Materializer bindings: the registry IS the format seam; languages land as spec families (TS, C# next)

- Status: Accepted (2026-09-07) — MoE-reviewed (three lenses: projection law
  → SOUND-WITH-AMENDMENTS; tiny-model ergonomics → CONDITIONAL PASS;
  generational skepticism → REFUTED the engine-unification, accepted the
  minimal binding; all dispositions folded into §Decisions)
- North Star impact: `clarifies` (ADR 0024 §2 / 0026 §1: the *spec* becomes
  a **binding** — the registry routes mechanically; no surface change, no
  new loop) + `applies` (internal to `xsoulspace_agentic_workspace`; gates
  already exist: span_edit_gate, pack_edit_gate, md/yaml materializer,
  edit_node_unified, etl_tick).
- Builds on: [0023](0023_filesystem_projection_target_edit_as_rederivation.md)
  (fs as projection target), [0024](0024_filesystem_one_map_graph_typed_materializers.md)
  (materializer specs as data), [0026](0026_workspace_domain_specs_as_data_wire_codec.md)
  (spec families as data), [0033](0033_derived_context_equation_mechanical_repair.md),
  [0034](0034_one_edit_verb_formats_grow_the_registry.md) (one edit verb,
  class-scoped action unions).

## Context — the storybook is converged; the ETL-out spine must not fork per format

The problem this project solves, in its own frame: the actor **writes a
storybook** — the meaning tree is the book, every decision is a beat, reads
are **raycasts** (`meaning_locate` + zoom projections over the map-graph),
and intents are an **open vocabulary** the model extends at runtime
(`intent_define` as data). ETL turns meaning into actions; materializers
turn actions into bytes. The storybook layer is CONVERGED (ADR 0033:
derived context; ADR 0034: one read program, ONE edit verb, class-routed,
creation included — measured 1,424 chars/4 → cutBudget 628, the 4k AFM tier
funds a cut). The model surface is closed.

What did not converge is the **ETL-out spine** — verified leaks:

1. **L1 — the registry describes but does not bind.** `MaterializerSpec`
   carries `emitter`/`oracle` as strings nothing reads; the real edit
   dispatch is a hardcoded `switch (node.kind)` in `edit_node_router.dart`.
   A new format means editing a switch — the per-format growth ADR 0034 §4
   forbade.
2. **L2 — the map half (ETL-in) is hardcoded in the fs tier.**
   `fs_etl.dart` holds `_mapClasses`/`_mapPrefixes` and a
   `_indexMdSections` / `_indexKeypaths` class switch. A new class means
   editing `fs_etl.dart`.
3. **L3 — the apply pipeline is duplicated (measured honestly: 2 verbatim +
   1 divergent cousin).** md and yaml/json applies are near-identical
   ~65-line `lock → capture → write → oracle → revert → finally` blocks.
   span_editor's apply is a DIFFERENT engine (multi-file all-or-nothing,
   approver-before-bytes, `SpanVerifyBaseline` failure attribution,
   subprocess oracles) — forcing it into the same machine is the fork the
   skeptic refuted.
4. **L4 — `SpanEditor` is a god class** (2,195 loc): ToolDef, four dart op
   planners, op-chain integration, the dart-tier apply engine, lexical
   utilities, the pack registry. Only the planners + fences are
   Dart-specific.

Trigger for fixing now: **TypeScript and C# land next** (first full-code
non-Dart languages) plus their config surfaces (`package.json`,
`tsconfig.json` day one via the existing json class; `*.csproj` needs a new
xml class). With the current spine each lands by editing switches; with the
binding registry each lands as data + one file.

## Decision

### 1. The binding law — routing keys on the node's `class` prop, never a switch

- **Routing key = `fileClass`** (the `class` prop stamped once by the ETL
  into every node — file AND sub-nodes), never `node.kind` and never a
  switch. yaml+json share ONE keypath materializer across two classes —
  kind-routing would duplicate it; class-routing already doesn't.
- The informal contract that already fits a 4th class (`perform({action,
  anchor, body}) → outcome.toJson()` + `MaterializerSpec.actions` +
  `materializerSpecFor`) is **promoted to a tiny type** — the
  `MaterializerBinding` record: `{fileClass, extensions, actions,
  materializer (perform fn), mapBuilder?, subNodePrefix?}`. At most ~20
  lines — the proven shape, made mechanical. NOT a fat interface: no
  nullable knobs for packs/consent/coverage/baseline (dart-only machinery
  stays on the dart path the router already maintains — `sym_*` nodes never
  route through the node binding).
- `edit_node_router` dispatches via the registry. The kind switch dies;
  no kind-based special case may return, including for dart.

### 2. The map half is engine-owned mechanics with binding-declared structure (L2)

- `fs_etl` calls `binding.mapBuilder` in the same zero-model-token pass;
  `_mapClasses`, the index switch, and the `_mapPrefixes` hardcode die.
- **Engine-owned** (never per-binding): the budget caps and green-screen
  facts (`maxMapFileBytes` / `maxMapNodesPerFile`, `map_skipped` /
  `map_truncated`) — the view is bounded, never refused, by the engine not
  by each binding's diligence.
- **Binding-declared**: the sub-node id prefix (stale-map drop ownership) —
  the tree never lies on file change. Gate: a test edits a mapped file and
  asserts no orphaned sub-nodes.
- Mapless class = no text read, structurally (unchanged, 0024 amendment):
  the span reader serves text only to nodes carrying a binding-derived
  span; mapless classes get node facts + the named bounce. Absence of
  registration IS the enforcement.

### 3. Registration-time honesty (the P0.5 registry-linter pattern)

At registration the host validates:
(a) binding ↔ FileClassSpec agreement (a binding for an unregistered class
is a wiring error TODAY — it misattributed as "class has no actions");
(b) extension sets are disjoint across bindings, or precedence is
explicitly declared (resolution is a total, once-stamped function:
path → class, fixed at registration, consumed read-only by the router);
(c) `actions` non-empty ⇒ a named oracle exists (the honesty law, 0024 §6,
moves from convention to assertion);
(d) anchors currency declared (the ADR 0034 disposition-1 pattern —
keypath, never a path).

### 4. SpanEditor decomposition — only the SAFE extractions now (L4, L3-partial)

| Extraction | Now / deferred | Why |
| --- | --- | --- |
| lexical utils (`_matchBrace`, `_matchParen`, `_topLevelCommas`, `_MemberSite`) → `dart_lexicon.dart` | NOW | pure functions, mechanically gated |
| pack registry + `EditExecutableWire` validation → `edit_pack.dart` | NOW | gated by pack_edit_gate + edit_pack_capture tests |
| md/yaml apply skeleton → ONE private shared helper | at the 3rd verbatim copy (toml or the xml class for csproj) | rule of three met at that moment; stays internal, no public API |
| **EditApplyEngine unifying span_editor.apply** | DEFERRED — trigger: a measured row proves the baseline/approver/atomicity parameterization isn't a fork | the auto-revert/failure-attribution semantics (preClean gating, approver-before-bytes, `SpanVerifyBaseline`) are load-bearing; flattening them into optional knobs is how revert-attribution silently breaks |
| dart planner + fences → `dart_binding.dart` | with the deferred engine work | same semantics live there |

Bounce-prose is NOT churned by the refactor (ADR 0034 disposition 1: the
bounce teaching is the funded surface, measured fits=true).

### 5. The model surface — mechanism-first, forever constant (tiny-model conditions)

- **Symbol classes REUSE the dart action names verbatim**
  (`replace_member_body` / `insert_member` / `remove_member` /
  `apply_executable`) — they are class-agnostic semantically. A new name is
  justified only by genuinely new semantics (e.g. c# `partial` merge),
  never by format.
- **ToolDef description = mechanism, never enumeration**: "an action legal
  for the node's class; the file node's `edit_actions` prop lists them" —
  the per-class union is paid only inside the illegal-action bounce.
- **The UNKNOWN-ID bounce goes mechanism-first** (bounded for every future
  class): the repair names the move (locate → zoom rows stamp the id) and
  points at the node's own props (`edit_actions` names the legal actions
  AND the anchor currency) — zero per-class recipe prose.
- **v1/v2 divergence is registry data, never prose**: ts/c# v1
  `actions` simply omits the body-composing action; the illegal-action
  bounce teaches the limitation mechanically; v2 adds the action to the
  spec — a data change, zero surface churn. **Gate: no `"ts"`/`"c#"`
  literal anywhere in router or bounce strings.**
- **Zero-arg-delta is a hard gate**: the arg shape stays
  `{action, symbolId, body?, anchor?}`. Any new slot (language, project
  path, target) re-opens the measured P0 class (18/8/10 ToolCallErrors per
  row, 59–109-generation loops). `surface_capability_diff` +
  registry-lint fail registration on any verb addition or arg-shape delta.

### 6. Language tiers — how TS and C# land

- **Tier A — mapless/other**: tree visibility, review-gate writes only
  (0024 §6). `.sln`, exotic formats start here.
- **Tier B — fs-tier binding**: typed sub-nodes + class actions.
  `tsconfig.json` / `package.json` land DAY ONE via the existing json
  class; `*.csproj` gets an xml binding (keypath-currency anchors, xml
  parse + semantic-diff oracle — the keypath materializer generalized).
- **Tier C — code-tier binding** (dart today; ts/c# staged):
  - **v1 (no model-composed code bodies)**: symbol map via a mechanical,
    dependency-light scanner (the repo precedent: regex md headings,
    indentation keypaths, `scanDartFile`) — MEMBER symbols included from
    day one (decision 2026-09-07: methods/functions/arrows/consts as
    `member` nodes under their declaring parent, so `replace_member_body`
    and `insert_member` have nodes to address; ADR 0035 §8 extends the
    same contract to dart's member gap) — with honest bounces on
    unsupported shapes; member-body edits arrive via **pack executables**
    (`apply_executable` — the trusted-author tier is language-agnostic);
    analyzer oracle (`tsc --noEmit` / `dotnet build`) + the package's test
    convention through `workspace_conventions`. The model composes MEANING;
    bodies are derived/host-verified — ADR 0019's verifiability law holds.
  - **v2 (op-chain back-ends, evidence-gated)**: the R6 op VM is
    language-agnostic; only the emitter is per-language
    (`compileOpChainBody` emits Dart today). TS/C# emitters land when a
    measured row pulls them; until then the omitted action IS the
    limitation (per §5).

### 7. tree-sitter — named, evidence-gated NOW (so the gate exists when temptation peaks)

ETL-in scales one of two ways: N dependency-light mechanical scanners
(honest bounces name extractor gaps) or ONE parser FFI + per-language
grammars as data. **No FFI dep lands until ALL of:**
1. ≥3 named mechanical-scanner failure classes (real bounces attributed to
   extractor insufficiency, not model error) — the three-failures rule;
2. a measured row: decision cost of the workaround (a ts/c# task that
   needed review-mode or failed) in the evidence ledger;
3. a spike proving grammar output maps to meaning nodes with zero
   host-authored expectations (ADR 0022 invariant);
4. budget proof the 4k AFM tier still fits with the new node kinds.

### 8. tree-sitter separability architecture (Amendment 2026-09-07: the
### spike scope; the FFI is a LEAF, never a dependency of the workspace)

The layering that keeps tree-sitter movable, isolatable, and reusable
(house precedents: `universal_storage_conformance`, the `*_raw` packages):

```
xsoulspace_agentic_workspace   — ZERO dart:ffi imports, forever
   │ consumes MappedNodes, owns the binding family registration
   ▼
SourceParser interface + ParserConformance suite   ← THE SEAM (pure Dart)
   ├── MechanicalScanner   (pure Dart; always available; honest bounces —
   │                        the graceful degradation when no dylib builds)
   └── xsoulspace_treesitter_raw  (the ONLY dart:ffi import — a LEAF pkg)
         parse(grammar, source) → TsTree → ONE span bridge fn
         → source_span spans → MappedNodes (generic interpreter)
```

- **The conformance suite is the isolation mechanism**: ONE battery of
  fixture files (decorators, generics, arrow inference, multibyte content)
  with node expectations DERIVED from fixture annotations — runs against
  BOTH implementations. The scanner↔tree-sitter conformance DELTA is the
  clause-1 evidence measured as data, not argued. The workspace never
  hard-depends on the FFI: where the dylib does not build, the scanner
  serves and the suite still runs.
- **Span bridge, once**: tree-sitter yields UTF-8 byte offsets; this repo
  runs on `source_span` / UTF-16 decoded-string units (the projection-law
  pin). ONE tested conversion (mandatory multibyte golden test — emoji/CJK
  offsets are the classic silent corruption) feeds every existing span
  prop, zoom clamp and splice unchanged. Pin the unit discipline in the
  leaf package's README.
- **Generators-not-raw-code (the per-language cost is DATA)**: tree-sitter's
  query/captures API (S-expression queries) + a node-kind mapping table
  (`{grammarNode: {kind, name: @capture, memberOf: ancestor:…}}`),
  interpreted by ONE generic walker written once. Per language = queries +
  table + fixtures. **Prefer the interpreter over a code-generator until
  measured** — parse cost dominates; codegen is a non-goal (anti-
  speculative). Tables are validated at load (unknown grammar nodes,
  unresolved captures, cycles in `memberOf` = named load errors).
- **Member symbols are part of the scanner spec from day one** (decision
  2026-09-07): methods/functions/arrows/consts map to `member` nodes under
  their declaring parent (`memberOf`), because `replace_member_body` needs
  a node to address — the R9.1 gap row (member-level symbols unindexed,
  even for dart) is closed by the same mechanism when the scanner families
  land; dart's member indexing rides the same SourceParser contract.
- **Spike scope (clause-3/4 pre-seed, one grammar, scoped):**
  1. `pkgs/xsoulspace_treesitter_raw`: `SourceParser` impl + FFI shim for
     tree-sitter-typescript; macOS/Linux dylib path first; pinned grammar
     revision; parser free/leak checks. Zero workspace imports.
  2. The span bridge + multibyte golden tests.
  3. The generic query+map interpreter (`GrammarMapper`) — written once.
  4. The TS mapping table (member symbols included) + fixture set.
  5. The conformance battery run against BOTH the v1 mechanical TS scanner
     and the FFI impl → the delta table is the deliverable.
  6. Budget proof: mapped node kinds through the graduated profile — the
     4k tier still fits (clause 4).
  7. Results row: `results_etl_grammar.md` — clauses 1–2 still need REAL
     task rows (the spike only pre-seeds 3–4; state that honestly).
- Non-goal: no wasm path, no grammar authoring, no windows dylib until the
  native path proves on the dev platform.

## Consequences

- A class = one binding registration (+ materializer file when new). The
  engine, router, fs tier, and model surface are closed code. ADR 0034 §4
  ("the registry grows, never the surface") gets mechanical teeth.
- The honesty law is registration-time asserted, not conventional.
- The 2-verbatim apply copies stay 2 until a real third pulls the private
  helper — duplication of two ~65-line blocks is CHEAPER than a wrong
  abstraction (skeptic verdict, accepted).
- **Measurement duty**: with ts+c# registered, the graduated profile must
  re-measure at cutBudget **≥ 628, fits=true** (registry growth is data;
  expectation delta 0 — any delta is a named row). R7e tiny-model gate per
  new class (one real ts edit, one real c# edit through the ONE verb). P0
  rows 2–4 re-run remains the union-enum graduation measurement.
- The `edit_symbol → edit_node` rename (ADR 0034 disposition 2) still lands
  in its own batch; this refactor is a separate commit series, never mixed
  with the rename.

## Non-goals

- No YAML/JSON behavior DSL (behavior is Dart; `spec_check` data
  descriptors are the only model-authored spec surface, later).
- No new package (ADR 0026 assigns the engine + registry to
  `xsoulspace_agentic_workspace`; an interface-package extraction waits for
  a second domain host, 0025 path).
- No cross-language `refs` edges (declared escapes until a measured row).
- No speculative xml/toml bindings — Tier B/C classes land when a real
  task pulls them (the xml class for `*.csproj` is the named exception:
  it is pulled by C# landing).

## Migration order (each commit suite-green)

1. NOW: `dart_lexicon.dart` + `edit_pack.dart` extraction (safe, gated);
   registration-time validation (§3); mechanism-first unknown-id bounce
   (§5); binding record + registry dispatch in the router (§1) — the kind
   switch dies.
2. NOW: fs_etl map ownership (§2) — `_mapClasses`/`_mapPrefixes` die;
   orphaned-sub-node gate test.
3. NEXT OPERATION: TS family (Tier B json day one → Tier C v1 scanner +
   packs + analyzer oracle), then C# family (Tier B xml binding → Tier C
   v1). Measurement rows per §Consequences.
4. DEFERRED (triggers recorded): private apply helper (3rd verbatim copy);
   engine unification with span_editor (measured row); op-chain
   ts/c# back-ends (measured row); tree-sitter (the four-clause gate).
