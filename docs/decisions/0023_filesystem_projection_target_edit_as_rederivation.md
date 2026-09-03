# ADR 0023 — The filesystem is a projection target: edit-as-re-derivation (R7)

- Status: Accepted
- Date: 2026-09-02
- North Star impact: `sub_star` — declares the boundary for the edit tier:
  the harness's code interface is the meaning tree, never the filesystem;
  file read/write are demoted verbs in the meaning profile. The sub-star
  cannot override the repo charter (five seams, code law, AE ownership all
  stand).
- Builds on: [0007](0007_extensibility_seams_and_conformance.md) (five
  seams), [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0014](0014_composition_surface_and_discovery.md) (locate),
  [0018](0018_meaning_view_zoom_projection_context_ownership.md),
  [0019](0019_code_law_absolute_long_horizon_tier.md),
  [0021](0021_problems_as_canonical_rows_project_repair_packs.md),
  [0022](0022_workspace_oracle_meaning_pipeline.md)
- Evidence: `pkgs/xsoulspace_agentic_harness/docs/agent/results_etl_scale.md`
  (repo-scale round-trip 10,649/10,649, flat cuts, frontier findings);
  `results_r6.md` (generation already materializes without file writes).

## Context

The repo-scale ETL verdict (results_etl_scale.md) proved the harness's
*containers* hold at scale — but the ETL itself ran as an outer-agent
script, not through the harness loop. Two structural problems follow:

1. **The actor's SEE at scale is not a harness capability yet.** The
   scan/zoom/impact logic lives in a host library callable by ordinary Dart
   programs; an actor inside the loop has no tool to build the tree or cut
   it. (Partial exception: `locate` already indexes identifiers as a
   "matrix" ray.)
2. **There is no lawful ACT for editing existing code.** Generation is
   closed (R6: meaning → workspace Dart). Modification still forces the
   model to `write` whole files (the run-graded arm — a named law
   violation) — meaning the harness cannot refactor at any scale, let
   alone repo scale, without breaking its own law.

The deeper reframe this ADR records: **files exist for human convenience
and slow editing.** The ETL tree is a deterministic, re-derivable graph of
the same structure. Once the tree is the actor's only code interface, the
filesystem becomes what it really is: **a cache of the last
materialization** — and an *edit* stops being a text diff and becomes a
change to the tree followed by re-materialization of the affected
projection. The North Star already made exactly this inversion for memory
("memory is a re-derivable projection, never a stored log"); this ADR
completes it for code.

## Decision

1. **The filesystem is a projection target, not the actor's interface.**
   In the meaning profile: `read` → `zoom` (ray-cast over the tree, budgeted);
   `write` → **edit move** (typed, semantic; host materializes the patch).
   Whole-file text never enters model context, never leaves model output.

2. **ETL enters through the five seams (ADR 0007):**
   - *touch world*: `repo_etl` tool — scan the workspace, build/refresh the
     meaning tree as WORLD state (the tree is re-derivable, so it is
     **never snapshotted**; incremental re-scan is driven by git
     status/mtime and is a mechanical persist tick);
   - *see*: `zoom` tool (meaningCut with query/focus/zoom/budget params)
     and `impact` tool (hard-capped, degree-ranked frontier);
   - *act*: the **span-edit materializer** (P4, unblocked by ETL spans) —
     ONE edit tool with a minimal closed enum:
     `apply_executable{executableId, symbolId, params}` (the primary verb —
     edit executables come from packs, §3 below) plus the only
     model-composed moves `replace_member_body(op-chain)` and
     `insert_member(op-chain)` (the R6 compiler compiles the body).
     Cross-file operations — rename, move, signature change — are
     **built-in edit executables in the default pack**, not core enum
     cases: hardcoding `rename_symbol` as a sub-action would be
     vocabulary-by-hand (ADR 0019 §4) and would repeat the B4 hard cut
     (2026-09-01), which deleted `tree_patch.dart`/`rename_symbol` as a
     parallel text-patch edit path. Precondition of the edit tier's
     existence: whole-file `write` is demoted in the meaning profile —
     otherwise the new path duplicates the old one and B4 repeats. All
     reference expansion bounces as structured data on ambiguity (same-name
     symbols, unresolved ids) — it never guesses; the analyzer is the
     oracle and auto-revert is the failure path. Batches are atomic (all
     patches or none, in-memory revert) with a mandatory lock pre-check
     over the single-writer table — batch is a property of the executable,
     never a second tool. `replace_member_body` carries three
     host-enforced fences: (a) expressiveness — only bodies within the
     closed vocabulary (pure/static-like; instance state, async, external
     APIs bounce as named data, never silently downgrade working code);
     (b) oracle coverage — a legacy member may be replaced only when the
     workspace-oracle ETL derives expectations covering it (uncovered →
     structured bounce: add coverage first, which routes to pack/operator);
     (c) integration — the compiled body must match the declared signature
     and the file's identifiers, checked before generation.
   - *verify*: `dart analyze` + the workspace convention (free oracles),
     auto-revert on failure (ADR 0021 mechanical tier);
   - *persist*: beats, verdicts, budgets — never the tree.
   - *materializer toolchain (adopted — official Dart-tools stack, all
     already in the dependency graph)*: `source_span` is the patch
     currency (byte-offset FileSpans; scanner props carry offset/endOffset;
     analyzer diagnostics interop via SourceFile.span — failures land in
     patch coordinates); `source_maps` records generated-range →
     meaning-node-id mappings for materialized output, so analyzer/runtime
     failures localize back to op rows mechanically (the B2 dialect for
     compiled code); `code_builder` (+ dart_style) is the Dart EMISSION
     backend behind the same fences — it replaces string assembly, NOT the
     closed vocabulary, and the VM-replay program stays the parity oracle.
     The materializer spec is data: `{span currency, map format, emitter,
     oracle}` — source_span/source_maps are language-generic; only the
     emitter field is Dart-specific. One emitter path per materializer
     (no string/builders duplication); splices never reformat the whole
     target file.

3. **Edit executables come from packs, not from the model.** AE know packs
   / project repair packs (ADR 0021) supply parameterized edit executables
   ("add field + getter + doc", "fix loop bound", "rename across refs").
   The model picks an executable id and fills bounded slots (R6 division of
   labor). The capture loop records novel resolutions back into the pack —
   self-improvement for code edits.

4. **Cross-file scale follows from the graph, not from bigger context.**
   Renames, moves, signature changes and their reference updates are
   frontier walks over `refs` edges (deterministic, hard-capped) — the
   pattern class that whole-file read/write handles badly at any context
   size.

5. **Future (recorded, non-binding): generational packages.** When
   structure is a derived graph, package and project layout become
   re-materializable artifacts: ephemeral packages with structural caps
   (max dependencies per symbol/module), dependency overrides admitted only
   when API-necessary and evidence-cited. Nothing in this ADR builds that;
   the tree makes it *measurable* first. Any such work needs its own ADR.

## Consequences

- New race track R7 in PLAN.md (a: ETL tools → b: span materializer
  [critical path] → c: daemon persistence → d: pack capture → e: on-device).
- The run-graded `write` arm is demoted to legacy-host-only once R7b lands;
  new meaning-profile tasks must not use whole-file writes.
- `code_etl`'s tree builder is the harness `see`-seam index (next to
  `locate`); the standalone probe remains dev tooling, never a parallel
  product path.
- Snapshot/restore scope shrinks to beats/verdicts/budgets; the 18s
  repo-tree restore finding is resolved by *not restoring trees*
  (re-derive instead). The super-linear restore of beat envelopes remains
  an open perf item for the persistence owner.

## Non-goals

- No free-form text patches from the model (the code law stands; body
  changes route through op-chains or pack executables).
- No filesystem-as-truth compatibility layer: tools that assume the model
  reads files (pi-style) stay in the direct/legacy host profile only.
- No generational-package work under this ADR (future ADR required).

## Validation

- R7a gate (landed with this ADR): `repo_etl`/`zoom`/`impact` are
  actor-facing registry tools; a scripted actor builds the repo tree and
  cuts/impacts it through the loop, LLM-free, bounded.
- R7b gate: a scripted actor performs a multi-file code change on a
  repo-scale world — locate → zoom → edit move → host patch →
  `dart analyze`/test green — with ZERO `read` and ZERO `write` moves.
- R7e gate: one on-device AFM edit through the daemon.
