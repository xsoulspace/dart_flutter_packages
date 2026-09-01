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

**Status (2026-09-02).** ADR
[0019](../../../../docs/decisions/0019_code_law_absolute_long_horizon_tier.md)
landed: the code law is **ABSOLUTE at every model size** (verifiability, not
artifact size — untrained/invented languages are the strongest case FOR it);
free-form text was never under the law (`evidence` tier); the
**long-horizon tier** (Phase 8,
[plan_long_horizon_tier.md](plan_long_horizon_tier.md)) is the headline
measurement — the 20-task suite is re-labeled the conventional tier
(expected, honest losses to direct-grammar agents are published); growth is
**intent-first** (intents as data + host verification — `intent_define`/
`intent_call`/closure/macros already landed; AE owns durable truth per D2;
IntentCall projects intents to MCP/WebMCP/ACP/platform), with model-proposed
intent growth sequenced as the successor to J/K. ACP status corrected: the
server exists (`dart_acp_toolkit`, intent-registry backend included); the
remaining editor gap is one harness-backed `AcpAgentBackend` + a live Zed
proof. CI gate: `test/long_horizon_multi_session_test.dart` pins
tokens/decision flatness **across session boundaries** (snapshot/restore),
complementing the within-run Phase 2 gate.

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
each item is an LLM-free-testable increment. **Status (2026-09-01): P1,
P2, P3, P5, P6 landed (P3 after a law re-review); P4 open.** Measured
tables: [results_stage_p.md](results_stage_p.md).

### P1 — Bridge cancel contract (LANDED 2026-09-01)

The two crashed pass@3 sets died to the AFM bridge
`generation_timeout` + Swift callback-after-delete VM crash. Fixed on both
sides: per-generation state + registry gating every callback path,
`xs_fm_cancel(gen_id)` (cancel BEFORE Dart teardown), generation ids in
payloads, `xs_fm_abi_version` stale-dylib detection, structured timeout
errors. Proofs: 26/26 Swift bridge tests (incl. 8 live sessions), fake-
bridge Dart tests (timeout → structured error + cancel recorded before
tear-down; stale payload harmless; subsequent generate succeeds). The
first post-B1 pass@3 set COMPLETED: intent_03 0/3, ZERO bridge crashes,
zero overflows (results_stage_p.md §1).

### P2 — J7 overseer actor (LANDED 2026-09-01; on-device gate still open)

Landed `lib/src/tooling/overseer.dart`: on goal-attempt exhaustion an
overseer actor spawns with a brief of ONLY the summary zoom + structured
gate failure + failing intent's chain dump; closed vocabulary via ONE
tool (`approve` / `repair(intent, notes)` / `escalate(reason)`);
`repair` re-opens exactly one intent's scope on the MOVER via
`openFreshDecision` (max 1 cycle; the attempt allowance widens
monotonically, never resets); `approve` never forces a pass; `escalate`
swaps to a higher `Model.tier` if declared, else structured FAIL.
Scripted repair test green (`overseer_scripted_test.dart`) through the
SAME driver as the AFM runs. On-device intent_03 pass@3 = 0/3 (honest
FAIL, classified blockers, bounded, idle).

### P3 — Safe-edit surface (LANDED 2026-09-01, REVISED against the law)

The original mission text proposed a model-visible `writeMode` parameter —
REJECTED in review: the model must never supply whole-file content (the
"model never writes code tokens" law). Landed instead: `JailWriteGateway`
on `FsToolsRoot` — a HOST write policy over every jail mutation (model
`write` moves AND materializer output) with `apply` (default) / `review`
(unified diffs + host approval; CLI `--diff-gate` / `--auto-approve`);
jailed read-only `git_status`/`git_diff` (bounded projections, same
pattern as grep/glob). The run-graded arm's whole-file-write teaching
prompt remains a NAMED contradiction, closed by P4 (below) — do not
extend the model-facing write surface.

### P4 — J3 slice (OPEN — the next lever)

Host package `xsoulspace_agentic_dart_meaning` (ADR 0015): analyzer parse
→ MeaningNode/MeaningProps WITH source spans → `act_with_project`
`open(path)` → edit moves re-emit ONLY changed spans. This is also the
law-closure item for existing code: the model edits meaning nodes and the
HOST re-emits spans — no whole-file content anywhere in the model's
surface. Tests: round-trip parity, span minimality, id stability.

### P5 — Persistent sessions (LANDED 2026-09-01)

Snapshot exclusions reconciled with the standing crash-recovery contract
(GoalVerified/LoopStuck/EscalationRequest never cross a restart;
OpenDecision/Agency/AwaitingResponse DO — crash-mid-decision recovery;
AttemptCount and ToolRoundCount DO) → a snapshot taken at idle restores
idle-resumable. Restart-survival
test green (2 moves → snapshot → kill → restore → one more decision →
gate passes, idle). CLI: `--session <store>` persists without resuming,
`--resume <store>` continues (task + jail from envelope meta).

### P6 — Editor host transport (LANDED 2026-09-01, task-per-invocation)

`coding_agent.dart --json` streams NDJSON events (run_start / decision /
pulse / run_end / summary) on stdout — the foundation for a VSCode/Zed
extension. Core learns no transport (D5); telemetry wraps the HANDLER in
the host. Schema documented in pipeline_coding.md; smoke-tested (every
line parses; counts match the run log). Daemon + MCP adapter post-scope.

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

## Stage M — delegation surface: a2a dogfooding (ADR 0019)

**Goal:** the harness is used as a real CLI coding agent (like pi), driven a2a
by another agent (pi) — real work delegation + real problems discovery, with
every delegation row doubling as Phase 8 evidence.

**Decision D8 — the goal vector carries verification criteria; the oracle
executor is generic host code.** Hardcoded per-task checkers conflated the
criterion (what proves the task done — ADR 0009: part of the goal vector)
with the executor (run a command → exit-0 — generic, already `RunGoalSpec`).
Resolution:

- **Default oracle = workspace convention** (LLM-free, zero per-task code):
  mechanically discovered in the jail — Dart package with tests →
  `dart test`; Dart package without tests → `dart analyze`; bare `main.dart`
  → `dart run main.dart`. Same oracle for every task in a workspace class.
- **`--check <command>`** carries a sentence-named criterion; explicit beats
  convention.
- **Model-proposed criteria as data** (M0b, follow-up): one native tool call
  proposes criteria (commands/expectations); the host executes them
  mechanically — the model proposes, exit-0 decides, never self-graded
  (same trust model as `intent_define`).
- Per-task suite fixtures (`--task`) remain as benchmark fixtures only.

Shapes (sequenced; each produces signal before the next is built):

- [x] `M0` — general oracle: `resolveWorkspaceCheck` (LLM-free fs resolver)
  + `taskFromSentence` uses it + `--check` override + honest failure when no
  convention resolves. LLM-free test (`workspace_conventions_test.dart`).
- [ ] `M0b` — model-proposed criteria as data (native tool call,
  host-executed, mechanically graded).
- [x] `M1` — sidecar delegation: pi drives `coding_agent.dart --json
  --backend open_router --runs 1` per delegation via process spawn; NDJSON
  events parsed; verdict + failure_class recorded. No core change (D5).
  **First delegation PASSED end-to-end** (delegated_calc, 11 decisions,
  `dart test exit=0`, 30s) and caught TWO real integration bugs — actor
  bound to a random `ModelId.create()` unresolvable by the router (actor
  never generated) and the empty `ModelRouterResource` overwrite (escalation
  + capacity silently degraded). Both fixed in the runner; evidence:
  `benchmark/runs/delegation_m1_evidence.md`.
- [x] `M2` — real-history replay miner (LLM-free):
  `tool/mine_delegations.sh` → delegation manifest JSONL (commit, parent,
  sentence, package, proposed tier). Known limitation, recorded honestly:
  commit subjects are weak task sentences ("fix: removed") — sentence
  refinement is a named follow-up (mechanical templating first; ONE
  structured decision only as a labeled exception per ADR 0013). Jail
  seeding from parent hashes is the M2b follow-up.
- [ ] `M3` — `HarnessAcpBackend` over `dart_acp_toolkit` (IntentCall repo):
  session/new → `--session` store, session/prompt → resume+inject,
  session/update ← NDJSON events, request_permission ← write gate review
  mode. Build AFTER ≥5 M1 delegations shape the API.
- [ ] `M4` — pi-as-actor: host-injected decisions (`openFreshDecision`) for
  external-agent messages on a shared thread (a2h2a). Same transport as M3
  plus world-state semantics.

Operating cautions: prefer `--backend open_router` until the P1 bridge crash
is fixed; pin model ids; one process per delegation first; `--auto-approve`
only inside a disposable jail.

## Stage N — the live squad: real tasks, multi-model actors, one world (ADR 0019)

**Goal:** delegate REAL tasks in this repository (analyzer issues, failing
tests) to a multi-model actor squad working one shared world — pi, human,
AFM, and OpenRouter models as peers — perfecting a2a and the harness on the
harness itself. No git tools: the write gate in `review` mode is the VCS
(pi/human approves diffs).

**Sequencing principle: world-first, daemon-second.** The squad is world
logic (the risk and the novelty); the daemon is transport (D5 — core learns
no transport) and comes last.

**Prerequisite discovered in design: per-file single-writer.** Real fs is
shared mutable state outside the ECS graph; two actors editing one file is a
race the flush coherence point does not cover. `JailWriteGateway` owns the
rule. First squad tasks must be FILE-DISJOINT (analyzer issues partition by
file; barrel+implementation pairs are ONE task).

- [x] `N1` — **analyzer task board** (LLM-free): parse
  `dart analyze --format=machine` → issues → file-disjoint board tasks, each
  a goal with a mechanical criterion (file analyzes clean). The board IS the
  problems-discovery artifact. Tests: `analyze_board_test.dart`.
- [x] `N2` — **multi-actor squad, single process**: per-file single-writer
  (`FileLockTable` + per-actor gateways, cross-owner writes rejected before
  the gate); per-actor run-graded verification (`commandByRegistry`, stamps
  ONLY the pending actor); **race fixed** — verification now runs as a
  registered task so `canSleep()` waits for pending verdicts (the P5 flake
  was the same race). LLM-free proof: `squad_driver_test.dart` — two actors,
  two disjoint tasks, one world, board drains, `expectIdle`.
- [x] `N3` — **daemon** (`harnessd`): `bin/harnessd.dart` +
  `HarnessAcpBackend` over `dart_acp_toolkit`; sessions = threads; world
  snapshot persisted per turn (P5); free task sentence + D8 workspace
  convention oracle.
- [x] `N4` — **pi joins (LIVE)**: pi drove `harnessd` over raw stdio
  JSON-RPC: initialize → session/new(cwd) → session/prompt → streamed
  tool_call_update/agent_message_chunk → verdict. Protocol **PASS**; task
  **FAIL (honest)**: deepseek-v4-flash exploration loop (26 decisions, no
  write, `dart test exit=1`) — failure class feeds N5. pi-as-escalation-rung
  (a2a to the strongest model in the squad) lands with N5; write-gate ACP
  permission round-trips are the named N4 gap (apply-mode inside the
  delegated workspace for now).
- [ ] `N5` — **squad hardening + metrics**. Headline (ADR 0020) — **DONE**:
  the **Cut Composition API** (`cut_composition.dart`): typed slots
  (goal/map/observations/lastVerdict), per-slot policies (dedup, drop-empty,
  capacity, recency render within observations), required slots as an INPUT
  GATE (`CutViolation`, never dispatched to the model), per-composition
  LLM-free conformance suite (`cut_composition_test.dart`, 7/7). Wired into
  `runCodingAgentOnce` (coder composition); flat ranked cut remains default
  for non-declaring flows. **Live validation**: the N4 failure task re-run —
  27→8 decisions, FAIL→PASS (write + self-verified run, 10.7k tokens);
  `goalFirst=true` every decision. Evidence: `delegation_m1_evidence.md`.
  Remaining N5 items: fs file graph as the `map` slot's provider (exploration
  becomes structurally impossible); roles as data (model ≠ actor: one model
  fields a whole squad, AFM offline included); a2a columns beside the K
  columns; AFM rejoins when the P1 bridge crash is fixed;
  pi-as-escalation-rung; write-gate permission via ACP.

Honest boundary: first squad tasks are file-disjoint analyzer issues and
failing tests in harness packages. Cross-file refactors wait for N5
coordination. Every squad task emits the standard row — dogfooding and the
long-horizon tier are the same activity.

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
