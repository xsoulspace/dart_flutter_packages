# Agent Harness — Plan

> Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness.
> Thesis: harness = intelligence amplifier; model = replaceable reasoning
> primitive. History and landed work: [history.md](history.md). Durable
> decisions: [ADR Index](../../../../docs/decisions/README.md).

The working model is a living, multi-linear game world. Memory was removed as
a primitive; now planning is too (ADR 0009). A1–A7 all landed as of
2026-08 — this file is now the record of what shipped and the standing rules.

---

## The plan (all landed)

### A1. Fair comparison baseline — **landed 2026-08**

The Phase 4 columns were not comparable (three verified confounds — see
[plan_fair_pi_comparison.md](plan_fair_pi_comparison.md)):

- **C1**: OpenRouter client flattens context into one user message (no real
  chat-completions shape, no real usage accounting).
- **C2**: AFM and OR ran different decision machinery (guided schema vs native
  tools).
- **C3**: No pi column — resolved by driving pi via its **SDK**
  (`createAgentSession()`), not an ACP server we never built.

Steps: C1 fix + A/B → decision-path unification pilot → tool-parity decision →
pi SDK driver → run matrix (`harness+AFM` / `harness+OR` / `pi+OR`, same model)
→ publish `results_comparison.md`.

**Result:** C2 confirmed as the dominant confound. Guided-schema arm scored
0/20 (2 tool calls total); native-tool-calling arm scored 6/20 (262 tool
calls). Same model. pi scored 19/20 on the native loop. The remaining
harness-vs-pi gap is edit quality, not decision machinery — the model can
act but writes wrong content. See
[results_comparison.md](../../benchmark/docs/agent/results_comparison.md).

**Implication for tiny models:** guided schema is a bottleneck, not an
amplifier, at this scale. Native tool calling should be the default decision
path; guided schema remains available via `--decision guided` for targeted
A/B. The harness thesis ("harness = intelligence amplifier") now has a clean
mechanism to test: A2 plan-frontier + decomposition should close the edit-
quality gap without changing the model.

### A2. Goals as vectors, plans as projections (ADR 0009) — *falsification passed; productionize*

**Status update (2026-08):** the falsifying experiment ran across all 20
suite tasks — **−39% LLM calls, −24% tokens/task, equal 20/20 pass rate**
([results](results_plan_falsification.md)). Not noise. Remaining work to
production shape, in order:

1. **Purity** — **landed 2026-08**: move the frontier policy off direct fs reads — predicates run
   as verifier tools behind seam 3, results become beats, policy stays pure
   (conformance suite in A4 applies).
2. `Goal` entity: direction + tool-callable success criteria + lifecycle;
   predicate tools enter via seam 3 (`run_tests`, `diff_check`, `ast_check`).
3. Step entities on a verifiability spectrum (`mechanical | observable |
   open`) with status machine and evidence-beat links; superseded steps stay
   queryable.
4. `OpenDecision.stepId` backlink → agency grants carry acceptance criteria
   in-frame.
5. Plan-frontier projection — **landed 2026-08**: `projectPlanFrontier()` now
   runs inside `buildSituation()` every decision. Open steps linked to goals
   via explicit `goalLink`/`dependsOn` traversal are rendered as a
   token-budgeted "PLAN FRONTIER" fragment; `OpenDecision.stepId` narrows
   to that step alone.
6. Mechanical step verification — **landed 2026-08**: `verifyStepSystem`
   runs on the mechanical schedule; executes the step's acceptance
   predicate as a seam-3 `verify_step` tool and flips `Step.status`.
7. Real-model probe: **ran twice** — see
   [results_plan_falsification.md](results_plan_falsification.md)
   (§real-model, §follow-up). Cumulative token accounting landed (real spend
   ~20× the old metric — prior published numbers are undercounts). Role
   prefixes exonerated by A/B. Root cause of baseline thrash identified:
   pre-existing fs-jail path rejections (present 156× in the Phase 4 log),
   masked then by the checker-retry loop. **Mitigations landed + re-probed:
   −36% calls, −50% cumulative tokens on real AFM; edit_05 passes with 1 call
   (baseline: 17, fail).** **Idle-coverage rule LANDED** (mechanical
   "idle + open goal ⇒ verify", bounded to 1 nudge — results §round 4) and
   **decomposition mechanics LANDED** (per-step criteria in-frame, zero
   close-out: scripted refactor tasks −44…−72% cumulative tokens at equal
   pass rate — `benchmark/adr0009_experiments.dart`). Next lever:
   real-model decomposition probe (decompose call via guided schema), then
   the Phase 4 matrix re-run under cumulative token accounting.
8. Decomposition as one agentic act per goal (amortized; escalation tier OK),
   fidelity measured via ADR 0004 causal coupling.

New metrics: mechanical-step share (work completed without any LLM call —
already measured at 100% for verification in the falsification run),
escalation rate per task class, decomposition fidelity via ADR 0004 causal
coupling.

### A3. Reduction fidelity / structurification (Phase 4b) — **landed 2026-08**

Keyword-drift recall measures *execution-context* quality for steps (plan
discovery uses explicit links and is drift-free by construction).
[test/reduction_fidelity_test.dart](../../test/reduction_fidelity_test.dart)
proves: reduced beats still trigger correct rays after mechanical
verification (evidence + observation survive budget pruning, decoys pruned,
frontier exact), and scripted success is causally gated — a step verifies
only when its evidence beat exists; without it the verdict fails with a
teaching-shaped message, never silently.

### A4. Seam conformance suites (Phase 5b) — **landed 2026-08**

[test/seam_conformance_test.dart](../../test/seam_conformance_test.dart)
(16 tests): policy determinism canary (double-evaluate identical drafts) +
purity canary (evaluation leaves the world surface untouched); nested-JSON/
unicode tool-result round-trip into beats losslessly; handler fault matrix;
verifier-tool conformance (pass→verified, fail→teaches+failed, throw/missing
executor→step stays open, determinism, timeout on the tool path); projection
budget breach degrades by documented silent truncation (tokens ≤ budget,
truncation flag, relevant kept / oversized pruned).

### A5. Snapshot/restore + baseline table (Phase 6) — **landed 2026-08**

Beats/threads/**goals/steps** persist via the harness codec
([snapshot.dart](../../lib/src/snapshot.dart)) through
`SnapshotStore` ([snapshot_store.dart](../../lib/src/snapshot_store.dart))
on `universal_storage_filesystem` (`StorageService`, one JSON document per
session). Facet index rebuilds from restored beats — derived state never
source-of-truth. Crash mid-decision: dangling `AwaitingResponse` taskId is
safe, `OpenDecision` re-opens, projections byte-match pre-snapshot (golden,
incl. goals/steps/tool-result beats). Headline comparison table published at
[results_comparison.md](../../benchmark/docs/agent/results_comparison.md).
Follow-up landed: the codec now runs on `PersistentId` identity — see
[A8](#a8-migrate-persistence-to-persistentid--landed-2026-08).

### A6. Everyday CLI host (thin) — **landed 2026-08**

[cli_host.dart](../../lib/src/cli_host.dart): streaming deltas
(`output`), input-as-decisions while idle (`feed`), cancel-in-flight = task
cancellation + agency release (`cancel`), `/situation` inspector
(`renderSituation()`), snapshot autosave seam (`onIdleTurnEnd`),
confirmation-gated tools (`confirmationRequiredTools`). The everyday REPL is
apple_foundation `bin/agent.dart`, rebuilt on `CliHost.start()` — hand-rolled
loop removed; `_stats/_trace/_spawn/_save/_load` retained as host extras.

### A7. Generational cleanup / architecture round — **landed 2026-08**

One dedup + garbage-collection pass across `xsoulspace_inference_core` ↔
provider packages (tests, benchmarks, examples, bins). Disposition rules:
lessons extracted → delete; live intent behind broken scripts → unify;
verbatim twins → one home; evidence artifacts stay tracked. Net: ~1.2k LOC
removed across 38 files; core 184/184, afm 16/16 (+ example 6/6), benches
8/8 green; no lib behavior change.

1. **Probes deleted** — `tool/probe_*.dart`, `tool/led_*.dart` (~480 LOC):
   mandated by the history.md cleanup ledger; lessons already live in
   `run_until_idle_tool_race_test.dart` and the support helpers.
2. **Real-model probes unified** — afm `coding_suite_plan_probe` /
   `coding_suite_decomp_probe` and openrouter `decomposition_probe_or`
   broke when their modules folded into `adr0009_experiments.dart`; now
   thin (~70-line) entrypoints over backend-injected arms in
   `benchmark/experiment_arms.dart` (`runPlanProbe` /
   `runDecompositionProbe`). Restores the A2 §7 real-model decomposition
   probe with one arm/table/trace implementation.
3. **Single homes** — `CumulativeTokenMeter`, `LoggingHandler`, and the
   chars/4 estimator (`benchmark/shared/`) replace their per-file twins in
   the suite runner, both phase benchmarks, and every provider bin.
4. **Test support promoted** — `runCycle`, parameterized `buildTestWorld`,
   and handler fault variants in `test/support/`; `_cycle` ×4, world
   builders ×6, oracle-driver clones, and near-clone mock handlers collapse
   into it. Drift fixed: single scene per actor in seam conformance,
   registry actually attached in failure guarantees, dead helper classes
   removed.
5. **Stale UI tests deleted** — both example `widget_test.dart`s asserted
   UIs that no longer exist (counter boilerplate / removed button); afm's
   was the package's only red test.
6. **Docs reconciled** — PLAN/history/results pointers updated to surviving
   entrypoints; afm AGENTS.md table matches disk (acp/ marked planned);
   afm justfile parses again (duplicate `test` recipe + make syntax
   removed).

Non-goals held: no lib behavior change, no new seams, no schema versioning.
Gravity check: serves (b) fewer calls and (d) LLM-free testable by removing
fourth/fifth copies of world bootstrap and accounting machinery.

### A8. Migrate persistence to `PersistentId` — **landed 2026-08**

Principle: `Entity` references are fine **at runtime** — graph wiring
(`ActorThreads`, `BelongsToThread`, `GoalLink`, …) stays as-is. But across
the serialization boundary they must never appear: `Entity` handles are
regenerated every run, so snapshots carry `PersistentId` identity instead,
translated back to fresh handles on restore.

[snapshot.dart](../../lib/src/snapshot.dart) rewritten onto
ecsly_serialization; the hand-rolled `_componentTypes`/`_encode`/`_decoders`
table is deleted — one serialization stack. Mechanics:

1. Capture stamps missing `PersistentId`s onto persisted entities
   (deduped carrier walk; runtime spawn paths untouched).
2. Per-type codecs encode every `Entity` field as its persistent id and
   decode through the target-world handle lookup — safe because the plugin's
   restore spawns all carriers before writing columns.
3. Structural filter drops derived/transient components (`Situation`,
   `StreamingBeat`, flow markers) from spawn signatures so they never
   materialize post-restore.
4. Facet-index insertion order — projection's recency tie-break consumes it
   and it is not derivable from components — is captured as `indexOrder` in
   the envelope and reproduced on rebuild.
5. `SnapshotStore` payload = `captureWorldSnapshot` JSON via the plugin;
   legacy payloads rejected with `SnapshotFormatException`.

E2E coverage ([persistent_snapshot_e2e_test.dart](../../test/persistent_snapshot_e2e_test.dart)):
payload identity stable across save→load→save (impossible under runtime-id
remapping); multi-actor cuts byte-match post-restore including privacy
filtering and tie-break order; a restored world keeps living — new scripted
turn appends beats, goes idle, and re-persists. Acceptance gates from A5 all
hold: goals/steps/tool-result golden byte-match, crash-mid-decision re-open,
corrupt/missing session errors. Core 210/210 green.


---

## Ahead — SWE push (M-series, started 2026-08)

Goal: push tiny-model SWE as far as declarative checking allows, with a
feedback loop fast enough to iterate per-hour. Framing: SWE on a 4B model is
a compression problem — minimize bits out of the model; maximize bits
through determinism; spend calls only at irreducible ambiguity.

- **M1 attribution ledger — landed.** `AttributionLedger` +
  `AttributedHandler` (fragment classes via wire-protocol prefixes:
  assistant/tool/absence/context) + `bin/harness_profile.dart` and
  `runProfile()` with a provider-agnostic handler factory. First scripted
  reading ranks tool-result bytes as the dominant context bucket (14.3k of
  16k on edit_05) — confirming compact op-diagnostics as the next lever.
- **M2 TransformFlow — landed (scripted gate).** DecisionFlow-style ETL in
  `lib/src/tooling/transform_flow.dart`: read-only `TransformContext`,
  guard-first stages (`onFile`, `onAnchor`, `when`), named stage outcomes,
  one mechanical mutator (`applyOps`). Anchor-patch = exact-match span
  replacement validated pre-mutation; applier re-checks = defense in depth.
  Wired end-to-end on a real suite family: `tasks_ops/refactor_patch_01`
  (fixture-seeded `lib/pricing.dart`, three deterministic checkers) run in
  both arms via `CodingSuiteRunner(extraTools: [patchFileTool])`.
  **Measured (M1 ledger, LLM-free): baseline 352 generated chars vs ops 144
  = 59.1% cut at equal pass and equal call count.** Ledger fix included:
  tool-call argument bytes now count as model output (whole-file writes hid
  their payload in rawOutput).
- **M3 tree-edit materializer — landed** (`tooling/tree_patch.dart`,
  `patch_symbol` tool): analyzer-parsed symbol replacement + canonical
  formatting; original and patched sources must both parse before any
  write. Tests: sibling members untouched, unknown symbol, invalid body
  rejected pre-write.
- **M5 protocol published** (`docs/agent/results_m5_protocol.md`) with ready
  commands and acceptance gates; execution awaits `OPENROUTER_API_KEY` or
  AFM unblock.
- **M4 AE bridge + M4b composition SDK — landed.** ae_core gains
  `Transformer`/`TransformContext`/`TransformerPipeline` (ports, exported;
  4 tests) extracted from the harness consumer shape. Harness side: (`tooling/ae_bridge.dart`): parses AE's
  schema'd `VerifyEntry.toJson()` wire shape into `AeGap`s, renders
  tier-ordered blocking-first beats, and registers a `verify_pack` tool
  (CLI executor; unit tests run on fixtures — no AE install needed).
  Typed AE import deferred until the Transformer port exists in ae_core.
  Guard still open: tiered diagnostics must beat prose retry feedback on
  one real task family before this replaces checker-prose feedback.
- **M5 real-model matrix re-run** under cumulative accounting + M1
  attribution (AFM when unblocked, OR-tiny proxy otherwise).
- **M6 externalization ladder — doctrine struck; stage 0 landed 2026-08.**
  Thesis restated operationally: move intelligence out of the model into the
  world's structure, projection discipline, and thread graph; the model only
  fills the next low-entropy micro-decision. First real evidence pair
  (edit_01_rename_constant, Apple Foundation, ops tools = fs + `patch_file`,
  tokens = M1 ledger chars):

  - native suspension: **PASS**, 1 decision, 26.5s — Swift ran
    read→patch_file→write inline; final prose claims an error while
    checkers pass (deterministic verification beats trusting narration).
  - guided schema: FAIL, 17 decisions, 195s — dec#0 emitted the CORRECT
    patch (schema fix validated); after the legitimate `anchor_not_unique`
    rejection the flat AnyOf loop echoed diagnostic tokens back as
    arguments for 15 rounds. Recovery steering, not arg emission, is the
    guided path's binding constraint. (Pre-fix run: FAIL at 125s — the
    model could not emit arguments at all.)

  Stage 0 changes: `patchFileTool` declares a real object `argsSchema`
  (before: guided Act branch had zero arg properties — `{"tool":
  "patch_file"}` was legal output; native calls treated all args as
  optional free-form); runner states seeded layout + relative-path rule in
  the system prompt (`_systemPromptWithLayout` — deterministic world facts
  never cost model rounds, applied identically to all arms/backends);
  `coding_suite_afm_ops.dart` defaults to native suspension per the A1
  finding, `--decision guided` kept for A/B, backend labels
  `afm-ops-native` / `afm-ops-guided`. Attribution caveat recorded: under
  native suspension, tool-argument bytes are generated inside the Swift
  loop and do NOT surface in rawOutput — generated-char buckets are not
  comparable across decision paths without this note.
  Remaining stages, gated on data: (1) plan/decompose arms on the
  refactor_patch01 family under attribution; (2) thin thread-fork probe
  using existing primitives ONLY — spawn K children via
  `DerivedFromThread`, stamp `ThreadScore` from checker pass-count, let
  scheduled prune/merge select; today no system produces forks and the
  scorer is a beat-count placeholder; (3) composition-surface ADR only if
  a probe wins against retry-with-checkers at equal wall clock.
  Non-claims: no ensemble/search gains asserted yet.
- **M6.1 loop breaker (mechanical guards) — landed 2026-08.** Question from
  the edit_01 guided failure: dec#0 was CORRECT (`anchor: MAX_USERS`) but
  legitimately rejected — MAX_USERS occurs twice in the fixture and the
  tool contract requires exactly-one-match; the model then echoed its own
  diagnostics as arguments for 15 rounds. Three deterministic tiers in
  `systems/loop_breaker_system.dart` (mechanical schedule, after
  processToolResults): teach at identical-failing-streak 2 (harness
  observation beat, projected like any other); raise-the-baton at streak 3
  (`EscalationRequest` on the actor — priority now, second model tier when
  registered); **fail fast** when taught-but-still-looping (suspend thread
  + withdraw the ReAct continuation marker). Measured on real AFM
  (guided arm): teach alone does NOT break this degenerate decoding
  attractor (context bloats, echoing continues to round cap, 237s);
  tier-3 stops it at **4 decisions / 30.8s vs 17 / 195–237s**, failure
  still classified honestly. Native arm unaffected (1 decision, PASS).
  Landed alongside, two engine fixes surfaced by the guard: (a)
  `attachBeatToActorThread` now RETURNS the thread and both beat-indexing
  call sites pass it directly — the old component read-back was null
  pre-flush within the same mechanical tick, so tool/response beats were
  wired to the graph but missing from FacetIndex membership; (b) noted for
  follow-up: `scoreThreadsSystem`/`pruneThreadsSystem`/`mergeThreadsSystem`
  query the `Thread` container component that `spawnThread` never stamps —
  they are currently inert against real threads (ThreadStatus is the
  actual marker). Accounting gap recorded: runner escalations count is an
  end-state snapshot; mid-run escalation tags consumed by responses are
  invisible — occurrence counting deferred until the second tier exists.
  Non-claims: the guard does not make the guided path pass; native
  suspension remains the default decision path per A1.
- **M7 candidate — harness-as-context-engine over CLI/MCP (dogfood).**
  Expose projection / facet-index / thread-graph / checkers as an MCP
  server so EXTERNAL agents (coding assistants working in arbitrary repos)
  get measurable context retrieval + deterministic verification. Rationale:
  every outside agent exhibits the same failures our tiny models do
  (context starvation, unverifiable edits); the projection cut is our
  measured answer. Gate: only after M6 stages 1–2 produce data.
  Falsifier: projection-based context pack must beat naive grep/ripgrep
  packing on a fixed retrieval benchmark at equal or lower token spend,
  measured with the same ledger discipline.

---

## Standing rules

- Every published benchmark column states backend, decision path, tokens
  source, and tool surface. Failures remain data.
- Escalation-rate metric ships next to every pass-rate table — quiet
  escalation means the tiny-model claim is failing silently.
- Extensibility ledger: three host entries against the same seam trigger a
  design conversation.
- Gravity check before structural work: (a) tiny model stays useful,
  (b) fewer LLM calls, (c) context bounded + derived, (d) LLM-free testable.
- Scope tripwires for A2 specifically: no replanning policy engine, no plan
  schema versioning, no planner agent. Steps in, projection out, checks fail
  loudly.
