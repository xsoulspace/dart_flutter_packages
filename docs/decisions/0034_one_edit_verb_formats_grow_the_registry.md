# ADR 0034 — One edit verb: edits address meaning nodes; formats grow the registry, never the surface

- Status: Accepted (2026-09-07)
- North Star impact: `amends` (0024 §2 — `MaterializerSpec.verb` becomes
  `actions`; the surface is ONE verb class-routed) + `clarifies` (0030 §2
  applied to the WRITE side: reads already converged, edits had not).
- Builds on: [0023](0023_filesystem_projection_target_edit_as_rederivation.md),
  [0024](0024_filesystem_one_map_graph_typed_materializers.md),
  [0030](0030_one_decision_one_program_surface_convergence.md),
  [0033](0033_derived_context_equation_mechanical_repair.md)
- Measured trigger: one-truth graduation row (2026-09-07) — the read
  program replaced locate/zoom/impact (2,078 → 1,371 chars/4), but the
  md/yaml edit verbs (`edit_section` 220 + `edit_key` 233) remained
  separate model-facing surfaces, and the pre-graduation variant
  (1,823) does NOT fit the 4k AFM tier (cutBudget 266 < 600 floor).

## Context — the format leak, verified

The goal (ADR 0015/0030 §2): the model works ONE language-agnostic edit
verb over MEANING NODES; a new format = a new registered materializer —
"the registry grows, never the model surface". The read side honors
this: the `meaning_program` `read` op serves a Dart span, an md section
and a yaml keypath through the SAME op — the node's class routes the
reader. The write side did not:

1. **`edit_section` args leak the format three ways**: `path` (fs-
   thinking — ADR 0023: the target is a projection; `edit_symbol` never
   takes a path), a format-specific op set (`replace_section | …`), and
   format-specific anchor semantics (heading vs keypath). The model must
   know WHICH format it is touching to pick the verb AND the op.
2. **The registry itself predicted the failure**: `MaterializerSpec`'s
   doc says "ONE uniform edit verb" — but the spec carried
   `verb: 'edit_section'`, so every registered class added a verb. json
   escaped a third verb only because yaml/json share keypath semantics;
   toml/ini/xml would each force another verb or overloading. The
   "boxes ability to work with different formats" concern is structural,
   not aesthetic: the surface cost is paid per decision, forever
   (the ADR 0030 §Context anti-amortization force).
3. **The tree already carries everything needed for routing** (verified):
   `sec_*` nodes carry `{path, class: md, span_start, span_end}`; `key_*`
   nodes carry `{path, class, keypath}`; and BOTH materializers already
   accept a node id as the anchor ("exact section label or section node
   id" / "dot/bracket keypath or key node id"). The router was one
   dispatch away; only the surface stood in the way.

## Decision

1. **ONE edit verb.** `edit_symbol` (name kept this iteration — the
   `edit_node` rename is named, deferred until after the on-device row)
   addresses ANY meaning node: `sym_*` (dart), `sec_*` (md sections),
   `key_*` (yaml/json keypaths), and future classes' node kinds. The
   model supplies `{action, symbolId, body?}` — never a path, never a
   format. The host resolves the node, reads its class, and dispatches
   to the class's materializer (splice + named oracle + locks +
   auto-revert: ALL existing machinery, class-routed).
2. **The action set is a closed union, class-scoped by the registry.**
   `MaterializerSpec.verb` → `actions`: the legal action names for the
   class (`md: replace_section, insert_section, append_to_section`;
   `yaml/json: set_key, replace_value, delete_key, append_list_item`).
   An action outside the node class's set is a NAMED bounce listing that
   node's legal actions — the model learns legality from the bounce and
   the cut, never by knowing formats. The per-class names stay (the
   semantics genuinely differ: splicing a heading section ≠ setting a
   keypath ≠ compiling a member body); what died is the per-format VERB.
3. **`path` leaves the model surface.** The node's props carry the file;
   the router reads it. This is ADR 0023 applied to edits: the target is
   a meaning node; the file is the projection.
4. **The declarative clue is the existing spec registry** (the
   mechanism the format concern asked for): a new class registers a
   `FileClassSpec` (extensions) + a `MaterializerSpec` (span currency,
   map format, emitter, oracle, anchors, actions) + a materializer —
   data and one file, zero new verbs, zero surface growth. The fs tier
   stamps `edit_actions` on file nodes so the tick itself surfaces what
   a class can do.
5. **Low-structure formats keep the honesty law** (0024 §6): a class
   with NO named oracle has NO edit actions — its writes route through
   `write_review` (human consents the diff). A `text` class may
   register a weak oracle (e.g. `span_intact`) only when that oracle is
   mechanical and named — never a silent raw write.
6. **What is NOT a leak** (recorded so the law survives review): `body`
   (prose/scalar as data) is authored content — writing the doc IS the
   task; it is format-agnostic and guarded by the class oracle. And the
   per-class action names are vocabulary, not format knowledge — the
   addressed node teaches them.

## Named-not-built — DISPOSITIONS (2026-09-07)

Each named item carries a disposition, not an open question:

1. **Parent-addressed creation — LANDED (this iteration).** The
   unification had silently REGRESSED creation: the pre-unification
   verbs accepted literal anchors (`set_key` on a not-yet-existing
   keypath; `insert_section` with a heading-bearing body) — the node-id
   router v1 could only edit EXISTING nodes. Restored within the one
   verb: `set_key {symbolId: <any node of the file>, anchor:
   <full new keypath>, body: <value>}` — the keypath is the class's
   DECLARED anchor currency, never a file path; md `insert_section`
   creation already worked on node anchors. Fixing it surfaced a
   PRE-EXISTING oracle bug: the set_key CREATE branch filled
   `plan.target` with the PARENT entry, mis-routing the envelope to the
   update case (`changed` instead of `added`) — never caught because no
   test exercised creation. `target: null` semantics restored; creation
   gated LLM-free (`edit_node_unified_test.dart`). The creation slots
   (`body`, `anchor`) + their teaching cost ~64 chars/4, absorbed by
   deduplicating description prose against the system prompt and the
   bounces: the row holds at **1,424 → cutBudget 625, fits=true** (the
   creation teaching lives in the UNKNOWN-ID bounce — mechanical repair
   teaching beats schema prose, which is paid per decision forever).
2. **`edit_symbol` → `edit_node` rename — DEFERRED, trigger = the
   on-device wave re-run.** The rename is string-mechanical (87
   references) and token-neutral; it lands in the SAME batch as any fix
   the wave run forces, so the surface is churned once, after the
   measurement — and not before (the parallel unification work in this
   area makes mid-flight renames a conflict hazard).
3. **Mutation ops joining `meaning_program` — DEFERRED, trigger = a
   measured row where read/edit alternation dominates tokens/decision.**
   It is NOT a wiring task: a program carrying mutations needs (a)
   TRANSACTIONAL semantics — staged splices, oracles over the staged
   result, one revert on any op failure (all-or-nothing, never named
   partial application); (b) CONSENT scoping — per-op consent inherited
   from the host gateway vs one consent for the program; (c) the
   one-move interpretation — a program IS the move (ADR 0027: the
   decision is the batch); a 3-op program is one decision's move, not
   three. These constraints are the design; the row pulls the build.
## Consequences

- **Measured (2026-09-07, one truth, LLM-free gate)**: the unified edit
  verb absorbed `edit_section` + `edit_key`; with teaching prose
  deduplicated (bounces and the system prompt carry the arg-shape
  repair), the graduated profile measures **1,420 chars/4 →
  cutBudget 628, fits=true** — the 4k AFM tier funds a minimal cut for
  the FIRST time (pre-graduation: 2,268 → 36; program-only: 1,858 →
  234). The md/yaml rows run on the graduated tier.
- The daemon's read world (the mechanical directive relay) converged to
  the same dialect: `harness_meaning_program {"ops":[…]}` replaced
  `harness_zoom`/`harness_impact`/`harness_locate` — one read dialect
  everywhere, or the tiny model learns two.
- The md/key ToolDefs remain in the workspace package for LLM-free
  materializer tests — they are no longer model-facing verbs.
- The on-device wave re-run (P4 flag + rows) lands on THIS surface: the
  graduation measurement and the unified-edit row are the same run.
