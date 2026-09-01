# Agent Harness — Plan (Stage J/K: general agent via harness-absorbed complexity)

> Forward/frontier record only. Landed work (Stages A–I, J1.1–J1.5) lives in
> [history.md](history.md); durable decisions in the
> [ADR Index](../../../../docs/decisions/README.md) (notably
> [0018](../../../../docs/decisions/0018_meaning_view_zoom_projection_context_ownership.md));
> benchmark numbers in `results_*.md` + `benchmark/runs/`. The coding
> pipeline end-to-end: [pipeline_coding.md](pipeline_coding.md).
>
> This plan is written so **another agent can build and wire every piece**
> reliably. Each stage is independently testable, LLM-free first, and ends
> with an `expectIdle`-clean harness test. Failures are data.

## CURRENT SITUATION (read me first — 2026-09-01, post hard-cuts)

- **Works, proven**: the generic loop (flat tokens/decision, 23/23 scripted
  suite); intent closure v1 with materialized-Dart parity; macros
  (5 moves vs 24); context overhead 1,496 ≤ 1,500 tokens (re-measured after
  the B1 collapse of `intent_define`); J1.5 loop bounds + flight recorder +
  Flutter profiler. **Landed (hard cuts, 2026-09-01)**: B1 — `intent_define`
  collapsed to ONE self-executing action (`define` REQUIRES specs, always
  wires `impl`; the contract-only no-op path is deleted; `redefine_chain` is
  an accepted alias); B2 — one structured failure dialect for unimplemented
  intents; B4 — legacy edit paths deleted (tree_patch/patch_tool/
  transform_flow/ops_handler + barrels); B5 — manual-schedule crutch tests
  deleted; B3/B7 — ONE on-device entry point `bin/coding_agent.dart` with
  the verifier wired inside the loop + bounded host repairs consuming
  AttemptCount; B8 — pass@3 protocol with per-run logs. Scripted LLM-free
  proof through the SAME driver: intent_03 PASS, bugfix_01 PASS.
- **Gate status (measured, results_stage_j15.md §7)**: run-graded tier
  **PASSES** (bugfix_01 pass@3 = 3/3 on-device, 1,153 tokens/run, zero
  overflows) — the pragmatic coding path for run-verifiable tasks is REAL.
  Intent tier still **FAILS 0/3** — but the failure class changed: no longer
  "no executor" (B1 killed it); now chains execute and return WRONG VALUES
  (inverted branch/jump wiring) or builds are incomplete (materialize never
  run, one intent re-defined 29×). This is **pure chain-logic correctness
  = J7/J8 overseer territory**. Do NOT spend more mover-only attempts on it.
- **Unmeasured (never claim PASS)**: the op-localized `return`-error fix
  (both interpreter + materialized Dart, parity-pinned) cut tokens/run
  25–46% in a crashed run but has ZERO completed on-device n — TWO pass@3
  attempts died to an AFM bridge crash (`generation_timeout` + Swift
  callback-after-delete VM crash after `Exceeded model context window
  size`). Infra bug in `xs_fm_bridge`, not the harness; harness budgets
  held in every completed run.
- **Not started**: J3 (Dart round-trip for existing repos — the
  existing-project unlock), J6 (scoped subtask worlds), J7 (overseer),
  K matrix beyond the two DoD tasks.

**Status (2026-08-28).** Stages A–I + J1.1–J1.5 landed (detail in
[history.md](history.md)); J1.5 landed after the fix-stage endless-loop
incident — its section lists the traced hazards and results.

**What is proven vs open (the honest ledger):**

| Layer | Status |
|---|---|
| Channel (context/feedback) | **Solved** — point-zoom acks: O(1) feedback; 12k→4.1k; no overflow in 95–145 rounds |
| Oracle (verification) | **Solved** — intent-graded checker over real `dart` subprocess; mechanical verifier loop |
| Repair (state mutation) | **Bounded, quality open** — `redefine_chain` absorbs accretion; every loop monotonic-budgeted (J1.5); remaining: model doesn't self-repair to wire executors (J1.4 blocker) |
| Model horizon | **Open** — 2–4k model loses the plan over 100+ rounds; run variance dominates |
| Generality of vocabulary | **Open** — materializers are hand-written per task; no Dart round-trip |
| Observability | **Solved** (J1.5) — pulse + flight recorder; two on-device loops caught by the monitor, both fixed (results_stage_j15.md) |

**The strategic bet:** AFM becomes a general agent not by seeing more but by
being asked for less — tiny selections over meaning; the harness owns
decomposition, state hygiene, verification, repair, and context. Every item
below is a host program or a data contract; nothing requires a smarter model.

---

## Target scenario (what "done" means)

Given an arbitrary **Dart coding task** (greenfield sentence OR existing
repo + issue) with **no external steering**, the agent:

1. decomposes the task into subtasks **as data** (AE canonical / FlowSpec),
   each subtask scoped into its own world/scope with its own oracle;
2. builds/edits the meaning tree through ONE collapsed surface
   (`act_with_project` + intent tools + macros) — never code tokens;
3. the host materializes to real Dart (diffs on existing code), runs
   `dart analyze` + the behavior-spec oracle, and feeds **localized**
   failures back (meaning-node addresses, not stack traces);
4. escalates along a ladder (tiny model → overseer actor → bigger model /
   human) when a subtask exhausts its retry budget, with the escalation
   ledger shipped beside every pass rate;
5. goes idle with every subtask graded.

Honest boundary: "any complexity" = *any task decomposable into the supported
meaning vocabulary*. The vocabulary grows per domain; domain materializers
live in host packages (ADR 0015). Dart is the first and reference domain.

## Committed decisions (standing; details in ADRs)

- **D1** — meaning tree is ECS world state; one projection law for beats and
  meaning (ADR 0009).
- **D2** — AE owns durable truth + verification; harness owns loop +
  projection; one-directional sync; no AE embed (ADR 0017).
- **D3** — one collapsed surface default; re-expansion only as a benchmark
  arm; **macro gate FIRED** (ADR 0018) — macros are now committed (`J1`).
- **D4** — intent closure: the built program's registry is part of the
  agent's world; `intent_call` doubles as the behavior oracle.
- **D5** — escapable transport; core learns no transport (ADR 0015).
- **D6** — meaning view is a zoom projection; move acks zoom to `point`;
  ray-cast hits are seeds; failures localize to op/meaning ids (ADR 0018).
- **D7** — **context is harness-owned**: the budget law must bound everything
  the model sees; native-session accumulation outside the harness is a bug
  class (ADR 0018; experiment `J2` decides the mechanism).

---

## Stage J — the concrete sequencing

### J1 — Macros arm + context budget (gate for everything)

**Goal:** make the bookmark executor pass on-device. Attack move density and
prompt tax together.

- [x] `J1.1` — composite sub-actions as **host programs** on
  `act_with_project` (closed enum extension): `add_chain(specs)` (build a
  full op chain, host assigns ids), `link_chain(edges)`, `redefine_intent(
  name, ops)` (**atomic drop + rebuild of one intent's chain** — the scoped
  repair that absorbs accretion without general deletion). Every macro
  returns a point-zoom ack + problems list (D6).
- [x] `J1.2` — prompt/schema budget: teaching moves into tool descriptions
  + teaching beats; `overhead_tokens` measured at **1487 ≤ 1500** of the
  4096 window (`intent_closure_budget_test.dart`, published).
- [x] `J1.3` — macro surface is closed + countable (stewardship probe);
  macro results identical to the equivalent primitive sequence (parity test).
  Suite task `intent_03_bookmark_macros` scripted green (suite count 23).
- [ ] `J1.4` (benchmark gate — MEASURED 2026-09-01, honest split): the
      RUN-graded tier PASSES (bugfix_01_off_by_one pass@3 = 3/3 on-device,
      zero overflows); the INTENT tier still fails (intent_03 pass@3 = 0/3,
      zero overflows, bounded repairs, blockers now precisely classified:
      branch-logic correctness + incomplete builds — no silent degeneracy,
      no no-op path). Moves/subtask met by the macros arm (scripted);
      on-device move counts are 10–48/run. Measured table:
      [results_stage_j15.md](results_stage_j15.md) §7.
- **Tests (LLM-free):** macro parity vs primitive sequence; accretion test
  (define → break → `redefine_intent` → oracle green); suite task
  `intent_03_bookmark_macros` (same oracle, fewer moves); suite count 22→23.
- **Benchmark gate (AFM):** bookmark executor passes at **pass@3 ≥ 1/3**
  with zero context overflows; moves/subtask ≤ 6; `overhead_tokens` published.

### J1.5 — Loop bounds + runtime observability (pulled forward from J6.4/J8.1; added 2026-08-28 after the fix-stage endless-loop incident)

**Why:** the repair/fixing stage went live before its bounds existed. Traced
hazards: (a) `RunGradedGoalPolicy` re-opens a fresh decision on every failing
verifier stamp and `ToolRoundCount` is reset by any text-only turn, so
fix→fail→fix cycles consume **no monotonic budget** — the only stop is
`runUntilIdle`'s 2M-tick StateError, which names no loop and no cause;
(b) driver-injected retries (AFM `intent_closure_afm.dart` upserts
`OpenDecision` directly) do NOT reset `ToolRoundCount` → retries start with a
silently shrunken round budget (non-deterministic starvation); (c) all run
state (beats, decisions, loop streaks, verdicts, tokens) is post-hoc — a
running harness is a silent terminal. Plan rule applied: *failures are data* —
a hung run currently ships zero data.

- [x] `J1.5.1` — **monotonic `AttemptCount`** (F1): every failing
  `GoalVerified` stamp via the verifier→policy path increments a component
  that is NEVER reset by prose turns. At `maxGoalAttempts` the policy stops
  re-prompting, stamps `EscalationRequest` with a structured reason
  (`failure class: goal_unverifiable`), and suspends the thread — the
  ladder's bottom rung (J8.1) landed early; the loop provably terminates.
- [x] `J1.5.2` — **round-budget semantics** (F2): fresh budgets come ONLY
  from `openFreshDecision` (host-injected new tasks/retries) or a text-only
  final answer; a monotonic `TotalRoundCount` keeps the lifetime ledger.
  Policy `thenOpen` re-prompts stay chain-bounded — a policy-name-based
  reset made composition flows unbounded (`prototype_from_sentence`
  regression, caught by CI and reverted); `RunGradedGoalPolicy` cycling is
  bounded instead by J1.5.1's `AttemptCount`.
- [x] `J1.5.3` — **`WorldInspector` + `HarnessPulse` + `FlightRecorder`**
  (F3/core): an in-world sampler emitting a typed per-tick snapshot —
  per-actor decision stack (prompt, origin, round x/cap, retries, attempts,
  last call/result, `LoopStuck`, `GoalVerified`), loop-smoke detector
  (repeated failing signatures + decisions-opened-by-policy histogram with
  the loop signature), token spend. `FlightRecorder` = ring buffer,
  auto-dumped on maxTicks StateError / SIGINT so headless runs leave a
  post-mortem. LLM-free testable.
- [x] `J1.5.4` — **`HarnessProfilerView`** (host): Flutter widget over the
  pulse — three panes: actor/decision stack, live beat timeline, meaning
  cut at the same zoom the model sees (`meaningView` reuse — "profiler
  shows what the model sees"). Lives in a host package (ADR 0015).
- [x] `J1.5.5` — **driver wiring**: AFM driver registers the inspector,
  resets `AttemptCount` on a FRESH task (not a repair retry), dumps the
  flight recorder on exit (pass, fail, or interrupt); K-column data
  (retries, verdicts, decisions) printed even for failed runs.
- [x] `J1.5.6` — **backend-error retry budget** (found BY the monitor on
  the first wired on-device run): `RetryCount` was reset by every resolved
  response, so a flaky backend alternating `backend_failed` ↔ tool-calling
  responses retried forever (255× identical prompts). Fix: the budget
  survives tool-call continuations (ADR 0004 chain semantics), resets only
  on a text-only final answer.
- **Tests (LLM-free):** attempt budget exhausts → thread suspended +
  `EscalationRequest`, world still `expectIdle`; retry decision resets
  round budget; total count monotonic; pulse snapshot shape (stack, streak
  detection, verdicts); flight recorder dumps on simulated exhaustion;
  flaky-backend loop bounded; detector counts cycles, not held-open
  decisions.
- **Gate:** no on-device fix-stage run proceeds without the inspector
  attached; every future "endless loop" incident report must cite the
  pulse/flight-recorder dump, not a bisect-by-code-reading.
- **Results:** [results_stage_j15.md](results_stage_j15.md) — full numbers
  incl. on-device validation (J1.4 still open; blocker now precisely
  diagnosed: meaning-executor wiring, no longer an observability blind spot).

## P — Pragmatic path: "develop Dart projects with this agent" (2026-09-01)

Goal: a developer can point the agent at a real project (CLI first, editor
host later) and get reliable, safe, verified work. Ordered by leverage;
each item is an LLM-free-testable increment.

### P1 — Re-measure the return-error fix (n=3, unblocks honest numbers)

The op-localized `return`-error fix (already landed, parity-pinned) has
ZERO completed on-device n — two pass@3 sets died to the AFM bridge crash.
Re-run `bin/coding_agent.dart --task intent_03 --runs 3`. If the bridge
crash reproduces, file/fix it in the bridge layer FIRST
(`xsoulspace_inference_apple_foundation/lib/src/native_bridge/`) — suspected:
the 5-min `generation_timeout` fires while the Swift side still holds the
callback; a VM callback-after-delete crash follows. A `cancel()` path on
timeout is the likely fix. Until then every intent-tier number is
pre-fix and stale.

### P2 — J7 overseer actor (the intent-tier lever; the ONE model-side fix)

Single-mover repair is at its ceiling (3 sessions of bounded 0/3 with
named logic bugs). Land the PLAN J7 slice: after the mover's attempt
exhausts, an overseer actor opens with `summary` zoom + the structured
gate failure; its closed vocabulary: `approve` / `repair(intent)` /
`escalate(reason)`. `repair(intent)` re-opens exactly that intent's scope
(a fresh decision with the chain dump from `validateMeaningProgram` + the
interpreter trace of the failing call). J8.1 rung 2: escalate to a bigger
tier via `Model.tier` (OpenRouter) only after the overseer fails.

### P3 — Safe-edit surface for existing projects (host seam, no core change)

- `write` gains a dry-run mode + a host-side diff gate: writes land in the
  jail, the host renders unified diffs, apply on approval. The MODEL always
  writes via the same tool; approval is a HOST policy wrapping the tool —
  ADR-0015-clean.
- Add jailed read-only `git_status`/`git_diff` tools to the fs surface
  (same pattern as `grep`/`glob`) — a coding agent on a real repo needs git
  visibility; without it, it re-reads files to guess state.
- `rename_symbol` is the only structured existing-code edit; keep it
  advertised while J3 is unbuilt.

### P4 — J3 slice: analyzer-backed `open(path)` + span-anchored edits

The existing-repo unlock (PLAN J3.1–J3.4, host package
`xsoulspace_agentic_dart_meaning`). Minimal viable slice for P: parse one
file → meaning nodes with source spans → `act_with_project` gains
`open(path)` + edit-moves that re-emit ONLY changed spans (no whole-file
rewrite) → `dart analyze` failures localize to meaning nodes (J4.1).
Round-trip parity tests on a fixture corpus.

### P5 — Persistent sessions (Phase 6 finish)

`snapshotWorld`/`restoreWorld` + `SnapshotStore` exist; finish: restore a
session with the facet index + budgets intact, CLI restart survival, and
one scripted test proving a resumed actor completes a task. Prerequisite
for a long-lived daemon host (editor integration).

### P6 — Editor host (after P3+P5)

Task-per-invocation first: an extension/CLI call streaming
`coding_agent.dart` output (pulse JSON) into the editor. Daemon second:
one world, actor+thread per task, MCP transport adapter (D5 — core learns
no transport). `HarnessProfilerView` becomes the IDE debug panel.

---

### J2 — Context ownership experiment

**Goal:** make D7 operational — the harness must own everything the model sees.

- [ ] `J2.1` — A/B in the AFM driver: (a) session-per-decision (reset native
  session each decision; history only via harness projection) vs (b)
  persistent native session. Instrument: content tokens per decision
  (from AFM error payloads when they fire), pass rate, variance.
- [ ] `J2.2` — if (a) wins (expected): the native client gains a
  `resetSession()` and the loop owns it; document in ADR 0018 follow-up.
- [ ] `J2.3` — deterministic client-side test: session reset produces
  identical first-token behavior; no cross-decision leakage.
- **Tests (LLM-free):** client contract test (reset is total; history comes
  only from `ActorGenerateRequest` projection).
- **Benchmark gate:** no context errors across 3 full bookmark runs on the
  winning arm; variance (pass/fail flips across 3 runs) recorded.

### J3 — dart_meaning: Dart round-trip (the "general" unlock)

**Goal:** work on EXISTING Dart — parse code into meaning, edit meaning,
materialize as diffs.

- [ ] `J3.1` — `dart_meaning` host package (per ADR 0015, lives in a host
  package, not core): **Dart → meaning** via the `analyzer` package
  (functions, classes, methods, fields, calls, control flow → meaning nodes
  kind-vocabulary `dart_fn`/`dart_class`/…; source spans kept on props).
- [ ] `J3.2` — **meaning → Dart diff**: edit-meaning → re-emit ONLY the
  changed units (span-anchored text edits); no whole-file rewrite.
- [ ] `J3.3` — round-trip parity: parse → materialize(parse-output) is
  byte-stable on a fixture corpus (formatter-normalized); id stability
  across re-parse (stable id = fqn + span hash).
- [ ] `J3.4` — `act_with_project` gains `open(path)` (imports a file into the
  meaning tree) and edit moves operate uniformly on greenfield and imported
  nodes.
- **Tests (LLM-free):** round-trip parity corpus; diff-minimality (edit one
  fn → exactly that fn's span changes); id-stability test; growth arm at
  1k/10k real-Dart nodes.
- **Benchmark gate:** scripted suite task `dart_edit_01` (rename + body edit
  on a fixture repo) passes intents/analyze oracles LLM-free.

### J4 — dart analyze as a localized verification beat

**Goal:** the compiler becomes part of the oracle, with meaning-node
addresses.

- [ ] `J4.1` — `analyze_check` host program: runs `dart analyze --format
  machine` in the jail; maps each diagnostic's span → meaning node (via
  `J3.1` spans) → emits structured failure beats
  (`{node: fn_12, error: ...}`).
- [ ] `J4.2` — verifier loop consumes analyze failures like checker failures
  (mechanical, no LLM); model repairs via meaning moves at the named nodes.
- **Tests (LLM-free):** seeded-error fixture (broken fn) → analyze beat
  names the right node; repair loop green.
- **Benchmark gate:** on the `dart_edit_01` slice, ≥ 80% of analyze failures
  repaired without oracle escalation.

### J5 — Behavior-spec oracles (universal tests at meaning level)

**Goal:** keep "model never writes code" while making the oracle universal.

- [ ] `J5.1` — generalize `intent_calls.json` into **behavior specs**:
  tables of `(intent, args, expect)` + optional state threading, authored by
  the host (from AE canonical / task spec), compiled to real Dart tests.
- [ ] `J5.2` — specs live as meaning nodes (`kind: 'spec'`) — part of the
  world, zoomable like everything else.
- [ ] `J5.3` — the `intents` checker becomes the spec runner; `runs` stays
  for exit-code tasks.
- **Tests (LLM-free):** spec compile → real dart test green/red; spec nodes
  appear in `summary` zoom; failure output localizes to spec row.
- **Benchmark gate:** oracle-tier column in the K matrix: spec-graded vs
  run-graded pass rate at equal tokens.

### J6 — Hierarchical subtasks with scoped worlds

**Goal:** complexity scaling via decomposition + isolation — never a longer
prompt.

- [ ] `J6.1` — task → subtask tree as data (`planFromSpec` extension):
  each subtask carries its own fixtures, oracle spec, and budget.
- [ ] `J6.2` — **scoped execution**: each subtask runs in a fresh jail +
  world (or scoped subtree); parent receives graded results + evidence only.
  Accretion cannot cross subtasks by construction.
- [ ] `J6.3` — composition step: host merges subtask outputs (imports into
  the parent world); cross-subtask conflicts surface as parent-level gaps.
- [ ] `J6.4` — retry policy per subtask (bounded), then escalate (J8).
- **Tests (LLM-free):** two-subtask fixture (fn + its caller) composed
  green; cross-subtask breakage surfaces as a parent gap with addresses;
  subtask isolation (poison in one scope never reaches another).
- **Benchmark gate:** a 2-level task (multi-file feature) passes scripted
  end-to-end; tokens/subtask flat vs single-task baseline.

### J7 — Overseer actor (zoom strategies across actors)

**Goal:** one actor takes small decisions (point zoom); a second holds the
bigger picture (summary zoom) and reviews diffs/validation evidence.

- [ ] `J7.1` — overseer spawns after each subtask attempt; sees ONLY
  summary zoom + oracle evidence (never raw tool noise); its decision
  vocabulary is closed: `approve` / `repair(intent)` / `escalate(reason)`.
- [ ] `J7.2` — overseer teaching beats land in the mover's thread
  (loop-breaker integration already exists).
- **Tests (LLM-free):** scripted overseer approves a green subtask; scripted
  `repair(intent)` re-opens exactly that scope; escalation request stamps
  `EscalationRequest` (counted in the ledger).
- **Benchmark gate:** mover+overseer pair beats mover-only recovery rate on
  the accretion case (run4's failure mode) — the K matrix records it.

### J8 — Escalation ladder

**Goal:** escalation becomes a mechanism, not just a metric.

- [ ] `J8.1` — ladder policy: mover retries (bounded) → overseer → bigger
  model (`Model.maxInFlight`-gated second entry in the router) → human
  (`ask_user` a2h already exists). Each rung increments the ledger.
- [ ] `J8.2` — escalation carries a **structured reason** (failure class
  from the deterministic failure-mode classifier), never raw noise.
- **Tests (LLM-free):** each rung fires on its trigger; ledger rows carry
  rung + reason; a fully-exhausted task still ends `expectIdle`.
- **Benchmark gate:** every published pass-rate table ships the ladder
  breakdown (standing rule, now structural).

---

## Stage K — benchmark protocol (publish-or-it-didn't-happen)

**Goal:** single-run claims are the weakest proof in the repo; make claims
reproducible.

- [ ] `K1` — **pass@k protocol** (k=3 minimum) for every on-device claim;
  report pass@k, variance (flips across runs), wall clock.
- [ ] `K2` — per-arm columns (standing rules): tokens/decision, cumulative
  tokens, `overhead_tokens`, moves/subtask, recovery rate, escalation rung
  histogram, refusal-recovery rate, oracle tier.
- [ ] `K3` — matrix rows to publish (each = one config, n≥3):
  1. `intent_01` write-arm vs `intent_02` micro-moves vs `intent_03` macros
     (scripted structure numbers + AFM where the gate allows);
  2. J2 session arms (a) vs (b);
  3. dart_edit slice: analyze-repair rate;
  4. hierarchy: single-task vs two-level subtask tokens.
- [ ] `K4` — evidence discipline: raw logs to `benchmark/runs/` with
  `<name>_<arm>_run<i>.log`; summaries to `results_stage_j.md` + ADR-indexed
  decisions; failures classified (context / divergence / capability /
  oracle), never dropped.
- **Acceptance:** every number in `results_stage_j.md` states backend,
  decision path, tokens source, tool surface, and n.

## Acceptance (end state)

1. [ ] Bookmark executor passes on-device at pass@3 ≥ 1/3, no context
   overflows, ≤ 6 moves/subtask, `overhead_tokens` ≤ 1500 (J1+J2).
2. [ ] Existing-Dart edit loop green: import → meaning edit → diff
   materialize → `dart analyze` localized repair → oracle green, LLM-free
   (J3+J4).
3. [ ] Behavior-spec oracle universal: greenfield and edit tasks both graded
   by compiled specs (J5).
4. [ ] A 2-level task passes via scoped subtasks with per-subtask oracles;
   isolation proven (J6).
5. [ ] Mover+overseer beats mover-only recovery on the accretion case; the
   escalation ladder fires with structured reasons and is in every table (J7+J8).
6. [ ] Benchmark protocol: pass@k + full column set for every published
   claim (K).
7. [ ] Every stage LLM-free reproducible; every harness test ends
   `expectIdle`; the model never writes code tokens, never sees an AST,
   never holds the whole tree.

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
