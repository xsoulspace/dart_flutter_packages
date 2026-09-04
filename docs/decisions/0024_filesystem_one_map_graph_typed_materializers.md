# ADR 0024 — The filesystem is one map-graph: typed materializer specs, uniform edit verbs, tiny-model-first surfaces

- Status: Accepted
- Date: 2026-09-04
- North Star impact: `sub_star` — extends the ADR 0023 boundary from Dart
  code to ALL file classes: the harness's interface to the filesystem is
  one meaning tree (map-graph with zoom), never raw file text; every file
  class is governed by a materializer spec as data. This sub-star cannot
  override the repo charter (five seams, code law, AE ownership stand).
- Builds on: [0018](0018_meaning_view_zoom_projection_context_ownership.md)
  (zoom projection, context ownership),
  [0019](0019_code_law_absolute_long_horizon_tier.md) (code law: prose
  never passes code gates),
  [0023](0023_filesystem_projection_target_edit_as_rederivation.md)
  (filesystem as projection target; materializer spec as data),
  [0021](0021_problems_as_canonical_rows_project_repair_packs.md)
  (oracle/auto-revert), [0014](0014_composition_surface_and_discovery.md)
  (locate/discovery), [0015](0015_domains_live_in_hosts_core_stays_generic.md)

## Context

ADR 0023 made the inversion for Dart: the meaning tree is the actor's only
code interface, `read`→`zoom`, `write`→edit move, edit-as-re-derivation.
But the R7 dogfooding analysis (PLAN §NOW) shows the actor's real work is
NOT only Dart: Markdown docs, YAML configs, JSON assets, scripts. The
naive next step — registering generic `read`/`write`/`glob`/`grep` tools
for those file types (the surface any conventional agent has) — is the
exact failure this project exists to avoid: it reintroduces whole-file
text into model context, reintroduces the write hole, and gives tiny
models an unusable surface. The filesystem must be treated with the SAME
principles as Dart: represented as a map-graph with zoom, edited through
typed materializations, verified by mechanical oracles — so a tiny model
does big things and a larger model does bigger ones.

## Decision

1. **One map-graph, not per-type tools.** The meaning tree covers every
   file: `dir` and `file` nodes always exist; a file class with a
   registered materializer contributes TYPED sub-nodes (dart → symbols
   with refs edges, md → section nodes with link edges, yaml/json →
   keypath nodes). One zoom verb family (ADR 0018: point/local/region/
   summary) serves all classes — the model navigates the filesystem the
   same way it navigates code.

2. **Materializer specs are data, registered per file class** (ADR 0023's
   spec, now the universal shape):
   `{fileClass, span currency, map format (tree sub-structure), emitter,
   oracle, anchors}`.
   - **md**: span = heading-delimited section; map = heading outline +
     link edges (code fences inert — ADR 0019); emitter = whole-section
     splice (byte-offsets preserved elsewhere; never reflows the file);
     oracle = 0-broken-links (the docs workspace convention).
   - **yaml**: span = keypath; map = key-tree; emitter = offset-based
     splice (the `yaml` package does NOT round-trip comments — re-
     serialization is forbidden; splice by source offsets); oracle =
     parse + intended-change semantic diff.
   - **json**: span = keypath; map = key-tree; emitter = stable
     re-serialization of the parsed tree is acceptable (no comments in
     canonical JSON); oracle = parse + intended-change semantic diff.
   - **dart**: already landed (member/executable spans, code_builder
     emitter, analyzer + tests oracle).

3. **One edit-verb SHAPE, emitted by the registry — never N bespoke
   tools.** Every materializer emits its edit move with the R7e rules
   (the intentcall registry pattern — canonical contract upstream, thin
   adapters, registration-time validation): a required anchor slot
   (label/keypath/section — resolved MECHANICALLY, ambiguity bounces with
   repair hints), bounded value slots, host-spliced materialization,
   oracle-checked, auto-revert with failure attribution. New surface
   vocabulary is data (an intent set + a materializer spec), never new
   tool cases (ADR 0019 §4).

4. **Escape-hatch policy (read/write are demoted, not deleted).** A file
   class without a materializer is NOT given raw read/write in the
   meaning profile. It is visible as a node; zoom-to-file may show raw
   text for SMALL files (budgeted, like any cut); mutation goes ONLY
   through `JailWriteGateway` review mode (unified diff →
   `session/request_permission` → the human allows/rejects; reject →
   never lands). Raw write never re-enters the profile by default — that
   is the ADR 0023 demotion holding for every class.

5. **Tiny-model-first gate (the anti-conventional principle).** A
   materializer is not "landed" until its R7e-style gate passes: a small
   (2–4k-class) model performs a REAL edit through the surface — one
   required anchor slot, mechanical resolution, measured fixed-token
   overhead (the meaning-profile overhead row, 1408 fixed tokens, is the
   template). Surface ergonomics are enforced at REGISTRATION time by the
   host program (the P0.5 ToolDef linter), never hoped for per model.

6. **Oracle rule (extends ADR 0019).** Prose never passes code gates;
   config edits never pass code gates; every materializer names its
   oracle. A file class with NO mechanical oracle has NO edit verb —
   review mode only. The oracle is the materializer's fourth field, not
   an afterthought.

## Consequences

- `repo_etl` generalizes: one scan pass indexes dir/file nodes for every
  file and typed sub-nodes per registered materializer (mechanical,
  zero model tokens — same refresh tick as today).
- The daemon's meaning profile gains the fs tier as ONE surface:
  zoom (all classes) + per-class edit verbs + review-gateway escape
  hatch. The gate-driver/extension clients see ONE uniform tool shape.
- Sequencing (PLAN): md first (docs are half of real repo work), yaml
  next (pubspec.yaml is the real config need), json trivially after.
- Failure classes bounce as named data (ambiguous section label, invalid
  keypath, emitter failure, oracle failure) — each feeds the intent-first
  surface-growth loop, not a guess.
- What this does NOT do: no generic `grep`/`glob` tools return to the
  meaning profile (the map-graph IS the search); no raw write path; no
  per-type bespoke tool registries; no oracle-less edit verbs.

## Gates (each names its proof)

| Gate | Proves |
| --- | --- |
| fs-tier e2e (fixture) | map-read → zoom → consented review write lands; reject → never lands |
| md materializer e2e | section replace lands; broken link bounces as named data; link oracle green |
| yaml materializer e2e | keypath change lands, comments preserved (byte-level), parse oracle green |
| tiny-model R7e gate per materializer | small model performs the real edit within measured token budget |
| real-repo dogfood e2e | one dart edit + one yaml edit + one md edit through the daemon, consented, graded, on THIS repo |