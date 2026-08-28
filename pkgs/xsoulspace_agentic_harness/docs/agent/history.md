# Agent Harness — History Ledger

Extracted from the former living PLAN so the plan stays forward-looking.
One entry per landed body of work; durable decisions live in
[ADR Index](../../../../docs/decisions/README.md), benchmark numbers in
[results_phase4.md](results_phase4.md).

## Landed

- **Run/execute tool (Gate A)** — `runTool` in `tools/fs_tools.dart`: jailed,
  time-bounded `dart run`/argv execute with stdout/stderr/exit-code capture,
  structured timeout/spawn-error, jail cwd resolution. `test/run_tool_test.dart`.
  Via `fsTools()` it is listed on the coding surface everywhere.
- **`runs` checker (behavioral oracle)** — new `CheckerSpec` type in
  `benchmark/coding_suite/checkers.dart`: a task only "passes" when its target
  actually executes exit 0 (LLM-free, real `dart`). The deterministic verifier
  can now grade that code runs, closing the gap previously reserved to content.
- **Run-graded goal loop (Gate B)** — `tooling/build_gates.dart`:
  `defaultGoalFlow()` + first-position `RunGradedGoalPolicy`; a goal advances
  by running code (the `run` tool stamps `GoalVerified`), so a passed run
  terminates and a failed run continues. `test/build_gates_test.dart`.
- **Human-as-actor / a2h (Gate C)** — `askUserTool` + injectable
  `HumanAnswerProvider` (+ `stdinAskUser` stdin default) in
  `tooling/build_gates.dart`: the agent pauses, raises a question/option menu,
  resumes on the typed answer as a tool result. `test/build_gates_test.dart`.
- **AE-ETL plan-from-matrix (Stage D)** — `planFromMatrix` in
  `tooling/build_gates.dart`: AE-style canonical matrix rows → Goal + Step
  components (raw→structured→planning as a host seam, ADR 0015/0017).
  `test/build_gates_test.dart`.
- **a2a team primitive (Stage C)** — `spawnActorBranch` in
  `tooling/build_gates.dart`: a second actor in the shared world with its own
  open decision. `test/build_gates_test.dart`.
- **Run-graded benchmark** — `bin/build_gate_benchmark.dart`: baseline
  (`defaultReAct` + content checkers) vs run-graded arm on build tasks at flat
  cumulative tokens (2503 vs 2503), both pass; the `runs` oracle locates
  broken output. `bin/harness_profile.dart --all`: 20/20 (scripted).
- **Tool-efficiency measurement** — `bin/tool_eval_profile.dart` + `observation/tool_metrics.dart`: measuring `[ToolRegistry]` wrapper records
  first-use, in-sequence reuse, cost-per-call, latency, failure streaks;
  `analyzeTools` → per-tool report. `test/tool_metrics_test.dart`.
- **Simplified tool surface** — `rename_symbol` unified with
  `rename_symbol_multi` (ONE tool, auto-discovers referencing files; removed
  from default surface). `rename_symbol_multi` kept as a deprecated alias.
- **Discovery tools** — jailed `grep` + `glob` in `fs_tools.dart`
  (ADR 0014 §2); token-bounded, deterministic, read-only. Registered
  everywhere `fsTools()` is, so every coding-suite arm inherits cheap find.
- **Structural `locate` ray-cast** — `tooling/locate_index.dart`: heuristic
  identifier index; definitions-first, jailed-relative, cappable, JSON
  round-trip for persistence / AE-affordance. `test/locate_index_test.dart`.
- **Dialogue/prose composed (host-placement demo, ADR 0015)** — a
  dialogue-archetype `FlowSpec` (free-form archetype label) renders to
  `DecisionFlow` and drives `HarnessLoop` to idle with a scripted handler
  (`test/composition_dialogue_e2e_test.dart`). Demonstrates how a host
  (e.g. `last_answer`) embeds the generic surface — the core still
  interprets no domain meaning (ADR 0015).
- **Cinematic projection** — `projectSituationSystem`: token-budgeted,
  relevance-ranked, thread-aware, green-screen-explicit `Situation`. System
  prompt + tool schemas counted against the real budget.
- **Memory removed as a primitive** — beats + `FacetIndex`; projection is a
  ray (keyword hits ∪ actor threads), not a per-actor list scan.
  `MemorySummary` is a beat kind produced only by the deliberate
  `summarizeThread` transform.
- **Multi-thread projection** — rays traverse all of an actor's threads;
  `ThreadStatus`/`ThreadVisibility`/`PrivateToActor` filter entry and exit;
  pruned threads deindex.
- **Targeted decisions** — `OpenDecision.threadId` routes beats + identity
  seeding to a thread.
- **Failure guarantees** — tool timeouts/errors after `AgencyPolicy.taskTimeout`,
  fail-fast on missing handlers, `maxRetries`, timeout sweeper for stuck
  `AwaitingResponse`. The loop cannot hang on a bad backend.
- **Escalation tiers** — `Model.tier` ranking; lowest strictly-higher tier wins.
- **Collision-free IDs**, **single tool-result path**
  (`ToolCallEvent → toolExecutionSystem → ToolResultEvent → beats`).
- **CLI/server ergonomics** — `HarnessLoop.runUntilIdle({maxTicks})`;
  jailed `fsTools(FsToolsRoot(...))` for VM hosts; REPL in
  `apple_foundation/bin/agent.dart` with streaming, `_stats`, `_trace`,
  `_spawn`, and prototype `_save/_load` JSON snapshots (local bin-file
  implementation — NOT the Phase 6 deliverable; see ADR 0009 §Relationship).
- **Metrics machine** — `MetricsCollector`/`MetricsReport` wired into
  `ScenarioRunner` and benchmarks.
- **Scenario stress-testing** — real-loop multi-actor scenarios against a real
  model (`docs/scenario_stress_testing.mdx`).

## Phase history (from North Star table)

| # | Phase | Result |
| --- | --- | --- |
| 1 | Docs & North Star | Done — claims separated from proofs |
| 2 | Long-horizon scaling | **Done** — flatness **1.07x** tokens/decision, latency **1.92x** @1,000 beats, budget never exceeded; CI-gated (`test/long_horizon_test.dart`) |
| 3 | Streaming through FFI | **Done** — `xs_fm_generate_stream_async` Swift bridge → `streamStructuredText`; TTFT ~8.3s cold; smoke `bin/stream_smoke.dart` |
| 4 | 20-task coding suite | Ran; results honest but claim-defining number low — see [results_phase4.md](results_phase4.md) and [plan_fair_pi_comparison.md](plan_fair_pi_comparison.md) for why columns weren't comparable (C1/C2/C3) |
| 5 | Concurrency gating | **Done** — `Model.maxInFlight`, per-model agency gating, `_spawn` battle-tested under serial AFM. Follow-up: scale `taskTimeout` with queue depth |
| 6 | Snapshot/restore | Open — REPL prototype only |

## Postmortem adopted as practice — idle-race bugs (fixed 2026-08)

Two bugs let `runUntilIdle` exit while async tool work was in flight:
(1) response-carried `ToolCallEvent`s had no `taskId`, invisible to
`canSleep()`; (2) completed tools resolved their task in the same microtask as
sending `ToolResultEvent`, leaving one Mechanical pass stranded. Fixes:
per-call `TaskHandle` registration + unconsumed-results check in `canSleep()`.
Regression: `test/run_until_idle_tool_race_test.dart`.

Practices:
1. Invariant "idle ⇒ nothing stranded" must be provable from world state.
2. Production-path tests only (`runUntilIdle`); manual schedule-stepping tests
   masked this class of bug.
3. Stranded-event assertion after every idle (`expectIdle` test helper).
4. Bisection probes over code reading; instrument boundaries first.

## Cleanup ledger (historical)

- ~~8 known-failing core tests~~ → fixed as Phase 4 blockers were cleared.
- Migrate/delete legacy manual-schedule tests (sleep + second-pass crutch).
- ~~Delete bisection probes (`tool/probe_*.dart`, `benchmark/debug_*.dart`)
  after extracting lessons into checks/tests~~ — done 2026-08-25 (A7): probes
  deleted; lessons survive in `test/run_until_idle_tool_race_test.dart` and
  the `expectIdle` helper (`test/support/agent_harness_support.dart`).
- Fold `discussion.md` into ADRs — done via ADR 0009; discussion.md is now an
  archive of the design conversation (threads/beats/projection theory).
