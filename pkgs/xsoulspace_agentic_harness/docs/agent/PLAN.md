# Agent Harness — Plan (THE RACE: real dogfooding, head-to-head numbers, migration)

> Forward/frontier record only. All landed stages (A–I, J/K, M, N) live in
> [history.md](history.md); durable decisions in the
> [ADR Index](../../../../docs/decisions/README.md) (notably
> [0018](../../../../docs/decisions/0018_meaning_view_zoom_projection_context_ownership.md),
> [0019](../../../../docs/decisions/0019_code_law_absolute_long_horizon_tier.md),
> [0020](../../../../docs/decisions/0020_cut_composition_api.md));
> benchmark numbers in `results_*.md` + `benchmark/runs/`. The coding
> pipeline end-to-end: [pipeline_coding.md](pipeline_coding.md).
>
> House rule for this plan: **the coding agent IS the coding agent.** Issues
> in its own packages are its backlog, delegated to its own actors. pi
> orchestrates and escalates; pi does not absorb fixes the harness can do.


## CURRENT SITUATION (read me first — 2026-09-02, post N5 + AFM closure)

**Proven (runtime-verified, not asserted):**

- On-device AFM coding: bugfix_01 pass@3 = **3/3** post-fixes (P1 closed:
  bridge suite 26/26 incl. live sessions; pre-flight context budget; Swift
  named codes). AFM is UNBLOCKED for the squad.
- Flat tokens/decision at scale — on the LEGACY projection (Phase 2 gate,
  1.07×) and across snapshot/restore sessions
  (`long_horizon_multi_session_test.dart`).
- The delegation loop works end-to-end: pi → CLI/daemon → world → verdict →
  evidence (`benchmark/runs/delegation_m1_evidence.md`).
- The Cut Composition API (ADR 0020) fixed the exploration-loop failure
  class: 27→8 decisions, FAIL→PASS on the traced task; conformance 7/7.
- Multi-actor squad, single-writer locks, per-actor verification, roles,
  a2a columns, analyzer board, replay miner + seeder: all LLM-free proven.
- M0b `declare_check`: model-proposed criteria as data, host-validated,
  mechanically executed. Escalation rung: budget exhaustion → operator
  guidance continues the SAME task (scripted proof).

**NOT proven (the race):**

- The head-to-head numbers: harness(OR/AFM) vs pi(OR, same model) on a fixed
  suite — never run. Tokens-per-task dominance is still a hypothesis.
- Flatness WITH the composition active (working set + map add constant
  tokens; the claim must survive the fix).
- The self-improvement loop has never turned on real material: the analyzer
  board, miner, and seeder exist; zero real harness issues have been fixed
  by harness actors.
- Editor: `harnessd` speaks ACP; no editor has connected.
- **The meaning tier can never pass a non-pre-wired task** (diagnosed
  2026-09-02, ADR 0022): its oracle replays host-authored expectations and
  never reads the workspace; the 14-op vocabulary bans arithmetic, loops,
  and intent-calls; the materializer emits VM-replay, not workspace Dart.
  Three independent closures — tracked urgently as R6.
- Large-model amplification ("small ×100 → large ×10000"): the tier system
  is built; no same-tools cross-size measurement exists.

**The strategic shift (this PLAN):** stop building mechanisms. Turn the
loops on real material, take the missing measurements, and migrate real
work onto the harness. The coding agent IS the coding agent: issues in its
own packages are its backlog, delegated to its own actors — pi orchestrates
and escalates, it does not absorb the fixes.

## THE RACE (tracks; each ends in a number or a live artifact)

### R1 — Self-improvement loop, LIVE (the core)

1. Build the real board: `dart analyze --format=machine` over the harness's
   own packages → file-disjoint tasks (N1 parser).
2. Delegate bounded batches to harness actors (AFM first — the local-model
   goal; OpenRouter for parity rows). File-disjoint only.
3. Every task: standard row (backend, decisions, tokens, failure class).
   Failures are data; fix flows the harness cannot fix itself are the ONLY
   things pi touches directly.
- **Done when**: ≥5 real issues fixed by harness actors, rows published,
  and the repo analyzes cleaner than before.
- **STATUS 2026-09-02: first cycle DONE, then SUPERSEDED by ADR 0021.** The
  first cycle (prose tasks to model actors) fixed 2 of 4 warnings at 107k
  tokens each, failed one at 448k, and needed the operator for 2 — the
  wrong shape. ADR 0021 replaces it: **problems are AE-ETL canonical rows**
  (`agentic_executables_wire/problem_wire.dart`), **repairs are
  PROJECT-GUIDED packs** (never core tables — every project has its own
  lints/linters/custom rules), the mechanical tier is a host span transform
  verified by the SOURCE ANALYZER re-run (the free oracle), and the
  meaningful tier exists only for classes without pack executables.
  Landed: `problem_board.dart` (Dart machine adapter → canonical rows, pack
  loader, coverage split, mechanical executor with apply/revert) — 7/7
  LLM-free tests incl. REAL `dart analyze` oracle and revert. The 7-cycle
  warnings now resolve at ~zero model tokens; a novel class is resolved
  once (meaningful tier / operator) and captured into the project pack.
  Other-language adapters: out of scope until the Dart loop proves out.

### R2 — Flatness WITH composition (claim hygiene)

Extend the long-horizon benchmark to declare the coder composition (+
workspace map) and assert flatness with the working set included. If the
composition broke flatness, that is a named finding before anything else
ships.
- **Done when**: flatness gate green with composition ON (and the number
  published next to the legacy 1.07×).
- **STATUS 2026-09-02: DONE.** `long_horizon_composition_test.dart` —
  composed cut flat over 300 decisions, budget never exceeded. The claim
  survives the working set.

### R3 — Head-to-head numbers (the claim since day one)

Minimal honest matrix on a fixed suite (mined replays + analyzer tasks):
harness(OR, composed) vs pi(OR, same pinned model), plus harness(AFM) as
the local column. Same tool class, same retries, stamped rows.
- **Done when**: `results_head_to_head.md` exists with the standing column
  labels (backend, decision path, tokens source, composition, n).

### R4 — Large-model profile (amplification, measured)

Declare the tier: `CutComposition.coderLarge()` (wider observations
capacity, deeper map, bigger budget) + `ProjectionBudget` scaling. Then the
same tasks run at both tiers → the amplification delta becomes a number.
- **Done when**: one suite task measured at both tiers, delta published.
- **STATUS 2026-09-02: DONE.** `coderLarge()` (observations 24) +
  `coderLean()` (observations 4, map depth 1) declared; `--profile large`
  wired. Same scripted task both tiers: 5852 tokens/4 decisions (coder) vs
  7703 tokens/5 decisions (coder_large) — 1.32× graceful scaling, zero
  overflows. Live cross-tier measurement on the head-to-head suite is the
  follow-up.

### R5 — Editor live (the surface)

One recorded live client session against `harnessd` exercising the full
contract: initialize → session → prompt → permission round-trip (write
gate) → verdict. Zed proper follows; the recorded session is the contract
proof.
- **Done when**: transcript committed to `benchmark/runs/`.
- **STATUS 2026-09-02: DONE.** Live session recorded:
  `benchmark/runs/r5_acp_session_transcript.txt` — initialize → session →
  prompt → streamed tool updates → 2 permission round-trips (write gate
  asked the client; client allowed; tools executed) → verdict PASS. Also
  caught the analyze-only trivial-PASS hole (fixed: no tests → honest null).

### R6 — Workspace-oracle meaning tier (URGENT — [ADR 0022](../../../../docs/decisions/0022_workspace_oracle_meaning_pipeline.md))

> **SCALE VERDICT (2026-09-02, later) — [results_etl_scale.md](results_etl_scale.md):**
> the mechanics hold at repo scale. Tier 2 (whole repo): 941 files →
> 11,590 nodes / 67,444 edges, ETL-out fidelity **10,649/10,649**, cuts
> **FLAT vs tier 1** (local/region 2,044 tokens at both tiers; summary ~70),
> latency 6–61ms, decomposition hard-bounded, text+matrix ETL into the same
> tree, model-visible Situation ≤ 4,000 tokens with beats + plan steps.
> Two findings fixed (stable-id collisions; frontier hard cap); one OPEN
> critical: **snapshot restore is super-linear** (67.4k edges → ~18.3s) —
> the remaining scale blocker, not projection.

> **STATUS 2026-09-02: FIRST TRACK DONE — the R6 gate is GREEN.**
> `pkgs/xsoulspace_agentic_dart_meaning` (new host package) + the vocabulary
> growth in core. Measured row (`results_r6.md`):
>
> - scripted (LLM-free), n=1, wall ~10s: **1 decision, 7,857 projection
>   tokens, `dart test exit=0`** on a greenfield workspace (failing suite,
>   no lib/ file).
> - vs the run-graded `write` arm on the same task shape (delegation M1):
>   11 decisions, 15,725 tokens — and that arm violated the law.
> - vs the pre-wired intent tier: 0/3 pass@3 at ~20k tokens (results_stage_p).
> - ZERO model code tokens (moves: `intent_define.define` only); ZERO
>   host-authored expectations (the table derives from the suite's own
>   expect() calls — provenance cited per row).
>
> Landed: ETL-in (`test_etl.dart` — declared signatures + greenfield
> inference from suite imports/literals), ETL-out (`dart_materializer.dart`
> — expression-stack → structured if/else compiler, named unsupported
> shapes), the runner (`workspace_meaning_runner.dart`), and the vocabulary
> growth (7 ops incl. `call` — intents now compose intents; parity +
> stewardship-probe tests updated to 21 ops).
> Honest tails: greenfield param names are inferred (`arg0:int` — suite
> literals carry no names); state-op chains have no workspace-Dart
> realization yet (VM-replay still grades them); on-device pass@3 through
> this path is the next gate.

Diagnosis (2026-09-02): the intent tier can never pass a real task as
built. Three closures:

1. **Oracle closure** — `wireIntentGradedGoal` + the `intents` checker
   replay HOST-AUTHORED expectations; the workspace's real tests are never
   read. D8 is reachable only via the run-graded arm's `write` (the law
   violation).
2. **Vocabulary closure** — `meaningExecutorOps` has no arithmetic, no
   comparison beyond `eq`, cycles hard-banned (no loops), and **no `call`
   op**: intents cannot call intents, so intent-first growth cannot
   compound.
3. **Materialization closure** — `materializeMeaningProgram` emits a
   generic VM replaying embedded JSON; no workspace-shaped Dart, so
   `dart test` can never grade it.

Fix (each LLM-free-testable; AE supplies the wire per its bidirectional-ETL
charter — `~/xs/agentic_executables/docs/ae_harness_etl_spec.md`):

- **ETL-in**: `xsoulspace_agentic_dart_meaning` turns failing workspace
  tests/analyze output into AE canonical rows → intent skeletons + derived
  expectation tables. The workspace oracle IS the expectation table (D8
  finally governs the meaning arm).
- **Materializer-out**: idiomatic-Dart target as a materializer spec
  (data); VM-replay stays as the interpreter-parity oracle only.
- **Vocabulary as data**: arithmetic/compare/string ops, bounded
  iteration, and a `call` op — added via the ADR 0019 §4 mechanism (spec +
  one-VM semantics + parity test), pulled by failing tasks, never pushed.
- **Division of labor** (ADR 0021 pattern): host decomposes; the model
  fills bounded slots as data; chains are never authored from scratch.
  P4 span edits are reframed as the editing-surface projection of this
  ETL, not the law closure.

- **Done when**: one real workspace task (e.g. suite-shaped `add(a,b)`,
  then a tic-tac-toe `winner()`/`move()`) passes `dart test` end-to-end
  through the meaning profile with zero model code tokens and zero
  host-authored expectations.

### R7 — Edit-as-re-derivation: the filesystem is a projection target ([ADR 0023](../../../../docs/decisions/0023_filesystem_projection_target_edit_as_rederivation.md))

The scale verdict proved the containers hold (flat 2,044-token cuts at
67k edges). What is NOT proven: the harness LOOP working that scale — the
ETL ran as an outer-agent script, and there is no lawful act for editing
existing code (whole-file `write` is the only path). R7 closes both.

- **R7a — ETL as seams (DONE 2026-09-02).** `repo_etl` (touch world),
  `meaning_zoom` + `meaning_impact` (see) are actor-facing registry tools
  in core (`lib/src/tools/meaning_query_tools.dart`, domain-generic), the
  dart_meaning host wires them to the code scanner (`repo_etl_tool.dart`).
  Gate GREEN: `pkgs/xsoulspace_agentic_dart_meaning/test/repo_etl_tools_test.dart`
  — the harness LOOP scans the harness package (repo-scale), zooms and
  impacts through the actor registry, LLM-free; `read`/`write` do not
  exist in the registry at all; Situation ≤ 4,000 tokens.
- **R7b — the span-edit materializer (CRITICAL PATH).** ONE edit tool
  (`edit_symbol`), minimal closed enum: `apply_executable` (pack-fed) +
  `replace_member_body`/`insert_member` (op-chain — the only model-composed
  moves, via the R6 compiler) → host span-anchored patch → `dart
  analyze`/test, auto-revert (ADR 0021 tier). Cross-file operations
  (rename/move) are DEFAULT-PACK edit executables expanding over the
  impact frontier — NOT core sub-actions: B4 (2026-09-01) deleted
  `tree_patch`/`rename_symbol` as a parallel text-patch path, and
  reintroducing rename as a hardcoded verb would repeat that mistake
  (ADR 0023 §2 records the resolution). Sequencing: op-chain moves prove
  the materializer first; frontier expansion (rename) second, with
  ambiguity bounce (never guess). Precondition: whole-file `write` is
  DEMOTED in the meaning profile when this lands — no parallel edit paths
  a second time. **Gate: a scripted actor performs a multi-file code
  change on a repo-scale world with ZERO `read` and ZERO `write` moves.**
  This is the critical path — R7c/d/e wire to it.
- **R7c — daemon persistence.** `harnessd` holds the world + tree keyed per
  workspace; tree is NEVER snapshotted (re-derivable — incremental re-scan
  by git status/mtime is a mechanical tick); snapshots persist beats,
  verdicts, budgets only. Resolves the 18s repo-tree restore finding by
  not restoring trees.
- **R7d — pack-fed edits.** AE know packs / project packs supply
  parameterized edit executables; the model fills bounded slots; the
  capture loop records novel resolutions (self-improvement for code edits,
  ~zero tokens for known classes).
- **R7e — on-device.** One real AFM edit through the daemon — the full
  North Star sentence end to end.
- Demotion (hard cut, lands with R7b): whole-file `write` is demoted to
  legacy-host-only; new meaning-profile tasks must not use it.
- **Distillation → planning seam (R7d sibling, AE-owned)**: AE's distill
  DELEGATION protocol (`ae.distillation.task.v1` → external agent →
  `ae.canonical.draft.v1`) feeds `planFromMatrix` — plans from prose intent
  (ADRs, standards, issues), the one planning source tests/diagnostics/
  frontiers don't cover. The distiller is a squad ROLE (offline, evidence
  tier, own cut composition — N5c machinery); distilled rows are
  evidence-tier, never auto-pass. Missing seam: `planFromMatrix` consuming
  canonical drafts + the `distiller` role composition (AE spec:
  `ae_harness_etl_spec.md` §Distillation ↔ harness planning). Harness NEVER
  builds its own text distiller — the tier tests' section-split is a
  fixture, not a product path.
- Future (needs its own ADR): generational packages — ephemeral packages
  with structural caps (max deps per symbol/module), overrides only when
  API-necessary. The tree makes structure measurable first (ADR 0023 §5).

## R3 status (partial — the honest remainder)

Harness columns ran (scripted tier delta above; OR free-form delegations
logged). The pi column needs the pi driver run (`benchmark/pi_driver` in
inference_core) — the only unexecuted piece of the head-to-head.

## Open tails (forward, not urgent)

- ADR 0021 follow-ups: pack CAPTURE loop wiring (meaningful-tier resolution
  → pack entry, closing the self-improvement loop mechanically); the
  meaningful tier's span-zoom cut (P4 pulled forward — the 448k failure is
  its economic justification); batch replay of mined rows; embedding
  retrieval behind the `relevance.dart` seam (optional); Zed/VSCode native
  integration; last_answer as the first embedded host.


## Standing rules

- Every published number states backend, decision path, tokens source, tool
  surface, and n. Failures are data (classified, never dropped).
- Escalation-rate breakdown ships beside every pass-rate table.
- Gravity: tiny model stays useful; fewer LLM calls; context bounded+derived
  (D7: harness-owned); LLM-free testable. `expectIdle` ends every test.
- The model never writes code tokens, never sees an AST, never holds the
  whole meaning tree. Materialization, verification, projection, macros,
  decomposition, repair = pure host programs (`Agent = G ∘ F`).
- No AE embed; no transport protocols in core; no domain materializers in
  core (ADR 0015). Plans are data, never prose.

## Cleanup / hard-cut ledger

- ~~Collapse overlapping edit paths (`patch_file` / `tree_patch` /
  `structured_editor`): fold into registry-truth surfaces once J1 macros
  replace their benchmark role; delete~~ — DONE 2026-09-01 (B4); moved to
  [history.md](history.md).
- ~~Delete legacy manual-schedule tests that mask the idle-race class~~ —
  DONE 2026-09-01 (B5); moved to [history.md](history.md).
- `dart_meaning` (J3) lands in a HOST package, not core (ADR 0015) —
  create `pkgs/xsoulspace_agentic_dart_meaning` when J3 starts.
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner
  subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** — drive
  a *running* Flutter app (semantic snapshots, tap, hot-reload) through one
  MCP tool surface; the harness sees the same `intent_call` shape over a
  transport adapter (D5). Unblocks after J1/J2 prove the on-device loop.
