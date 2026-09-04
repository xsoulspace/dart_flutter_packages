# Agent Harness — History Ledger

Extracted from the former living PLAN so the plan stays forward-looking.
One entry per landed body of work; durable decisions live in
[ADR Index](../../../../docs/decisions/README.md), benchmark numbers in
[results_phase4.md](archive/results_phase4.md).

## Landed

- **R7 production path COMPLETE — #1–#7 gated with published rows
  (2026-09-04, macOS 26.6.2, real AFM + real pi)**: (1) the FULL edit
  surface over ACP — the scripted mover's prose directives are gone; the
  id-bearing verbs travel as structured JSON payloads (`harness_edit`/
  `harness_impact`) and the mover never guesses ids; (2) the
  meaning-profile overhead row — 1408 fixed tokens, fits the AFM window
  with 2392 working memory left; (3) packs as the PRIMARY path — the ADR
  0021 capture loop records verified-green novel resolutions into the
  project pack (`.dart_tool/harnessd/edit_pack.json`, mechanical
  fingerprint id) and every `edit_symbol` auto-realizes it; (4) the
  REMOTE MOVER — the daemon runs MODEL-LESS, every decision round-trips
  as `session/propose_move` (bounded cut + tool schemas + budgets out,
  typed tool calls back; the ACP toolkit gained `AcpMoveProposing`,
  symmetric with `request_permission`); (5) the persistent daemon —
  single-instance per workspace (exclusive lock; a second daemon exits
  2), warm attach over a unix socket (second session continues ONE
  world, ~0–1 ms startup, zero re-scan), keep-warm with idle-exit, AOT
  composes with the native-assets hook (no fallback); (6) R7e — **pass@3
  = 3/3**: the real on-device AFM model performed the pack-fed edit in
  ONE decision (2,008 tokens, 45% of the window); (7) the real-model pi
  row — pi's model drove the MODEL-LESS daemon (8 decisions = 8
  round-trips). R7e's failing runs found the predicted failure classes
  and the surface was tuned WITHOUT touching the law: optional schema
  slots get dropped by the 2–4k model (measured), so `symbolId` became
  the ONE REQUIRED id, `executableParams.symbolId` is promoted (the wire
  declares the slot), `label` resolves mechanically with ambiguity
  bounces; the free-form run tool in the meaning profile was a WRITE
  HOLE (`perl -pi` reached the file — measured) and is now constrained
  to the convention commands. Rows + transcripts:
  [results_r7.md](results_r7.md). Gates: `span_edit_gate_test.dart`,
  `edit_pack_capture_test.dart`, `meaning_profile_overhead_test.dart`,
  `harnessd_r7c_test.dart`, `harnessd_remote_mover_test.dart`,
  `run_allowlist_test.dart` (harness pkg);
  drivers `run_r7_daemon_gate.mjs`, `run_r7_warm_attach_gate.mjs`,
  `run_r7_pi_remote_mover_gate.mjs`.

- **Hard-cut pass: coding-agent deliverable + legacy edit paths (2026-09-01,
  Stage J continuation — B1–B8 cuts)**: (B1) `intent_define` collapsed to
  ONE self-executing action — `define` REQUIRES specs and ALWAYS wires the
  `impl` edge + validates the chain host-side; the contract-only no-op path
  (the J1.4 on-device blocker: the model picked `define` without specs, then
  could not recover from `intent_call` failures) is deleted; `redefine_chain`
  survives as an accepted alias for one release. (B2) ONE structured failure
  dialect for unimplemented intents (intent name + defined set + the exact
  repair move), shared by `intent_call`, the in-process interpreter, and the
  materialized program (template inlines it; parity pinned). (B4) legacy
  edit paths deleted: `tooling/tree_patch.dart` (628 lines incl.
  `patch_symbol`/`rename_symbol`), `tooling/patch_tool.dart`,
  `tooling/transform_flow.dart`, `benchmark/coding_suite/ops_handler.dart`,
  the `tasks_ops` fixture, and all barrel exports — `grep -r
  "tree_patch\|patch_tool\|transform_flow" lib/` is empty; superseded by
  `act_with_project` + `fs_tools` (read/write/list_dir/glob/grep/run).
  (B5) `test/harness_headless_tools_test.dart` (manual-schedule crutch,
  50 ms sleeps) deleted; its two unique coverage pieces (per-agent handler
  routing, runtime model swap) ported onto `runUntilIdle` in
  `test/handler_routing_test.dart`. (B3/B7/B8, host package
  `xsoulspace_inference_apple_foundation`) ONE entry point
  `bin/coding_agent.dart` (+ `lib/src/coding_agent_runner.dart`): jail +
  fs_tools + act_with_project + intent tools, session-per-decision AFM
  bridge, `AgencyPolicy(maxToolRounds: 12)`, intent-graded OR run-graded
  verifier wired inside the loop, bounded host repairs via
  `openFreshDecision` consuming monotonic `AttemptCount` against
  `maxGoalAttempts` (measured: the AFM native tool-loop runs a whole ReAct
  chain inside ONE decision, so the pending-marker trigger never fires —
  driver-level repairs must consume the same budget), pass@k protocol with
  per-run logs + summary rows in `benchmark/runs/coding_agent_*`. Shared
  meter/SIGINT extracted into the runner lib (one implementation). Also:
  the intent-graded verifier's in-process replay now starts from
  `initialState()` (the actor's own `intent_call` state no longer leaks
  into the oracle replay — tier-2 semantics; regression test in
  `build_gates_test.dart`).

- **Stage J1.5 — loop bounds + runtime observability (2026-08-28)**: the
  fix-stage endless-loop fix. Traced hazards: `RunGradedGoalPolicy`
  re-prompted on every failing verifier stamp with NO monotonic budget
  (`ToolRoundCount` was reset by prose turns), host-injected retries started
  with a silently shrunken round budget, and a running harness was a silent
  terminal. Landed: (F1) monotonic `AttemptCount` + `AgencyPolicy.maxGoalAttempts`
  — at budget the policy stamps durable `GoalAttemptsExhausted` (+ transient
  `EscalationRequest`) with a structured `goal_unverifiable` reason and
  suspends the thread: the loop provably terminates, `expectIdle` holds;
  (F2) `openFreshDecision` — the ONLY budget-reset path (host-injected
  fresh decisions; policy `thenOpen` re-prompts stay chain-bounded — a
  policy-name-based reset made composition flows unbounded, caught by
  `prototype_from_sentence_test` and reverted); monotonic `TotalRoundCount`
  ledger; (F3) `observation/harness_inspector.dart` — `sampleHarness` →
  `HarnessPulse` (per-actor decision stack, round/attempt budgets, verdicts,
  loop-breaker streaks, last tool signature/result) + `FlightRecorder`
  (ring buffer, identical-prompt re-prompt detector, dump on maxTicks
  StateError and SIGINT). `HarnessLoop.runUntilIdle` auto-samples a wired
  recorder and appends its dump to the maxTicks StateError. Host side:
  `pkgs/xsoulspace_agentic_harness_flutter_profiler` (`HarnessProfilerView`
  — decision stack, warning banners, meaning-cut "what the model sees"
  pane, flight-recorder-backed polls). AFM driver wired: recorder +
  `openFreshDecision` retries + pulse/dump published even on failure.
  **ecsly lesson (pinned by convention)**: new Component registrations MUST
  be appended at the very END of `AgentPlugin.install` — ecsly assigns
  component ids in registration order; mid-chain inserts shift host
  registrations' ids → "Column should exist after archetype creation".
  Tests: `test/loop_bounds_inspector_test.dart` (8), profiler widget tests (3).
  Benchmark: `tool/j15_benchmark.dart` — pulse overhead 13–21 µs (≈2% of the
  1kHz tick budget), incident replay bounded at 136 ms / 3 attempts.
  **On-device validation (archive/results_stage_j15.md):** the wired monitor caught
  TWO loop classes live — (1) `RetryCount` reset on every resolved response
  made a flaky backend retry forever (255× identical `backend_failed`
  prompts) → fixed as J1.5.6 (budget survives tool-call continuations);
  (2) the detector's own false positive on held-open decisions (60 s
  generation sampled 100-tick apart) → detector now counts open→closed→open
  cycles. Post-fix on-device run: decisions 7→4, tool rounds 51→19,
  projection tokens −31%, honest bounded FAIL (model never wires a meaning
  executor — the precisely-diagnosed J1.4 blocker).

- **Stage G — AE wire port + canonical→meaning-tree ETL (2026-08-28)**:
  `ae_bridge.dart` reduced to a host shim over the new AE-owned
  `agentic_executables_wire` package (typed tiers, gap-beat renderer,
  deterministic canonical→meaning-tree export); `planFromSpec` imports an AE
  export into world state preserving canonical ids — one id vocabulary across
  verify gaps, the model's cut, and the plan. `test/plan_from_spec_test.dart`.
- **Stage H v1 — intent closure (2026-08-28)**: `intent_define`/`intent_call`
  tools + `IntentRuntime` (host executors over the meaning view); modify =
  re-define; `wireIntentGradedGoal` stamps `GoalVerified` from scripted intent
  calls; suite `intents` checker grades real `dart` subprocess behavior of the
  materialized `program.dart` contract; task `intent_01_bookmark_manager`
  (suite: 21 tasks, scripted green). `test/intents_test.dart`,
  `test/intents_checker_test.dart`. Committed argument (was D4): the intent
  registry is **one truth, two projections** — behavior oracle in-world
  (`intent_call`, no stdout parsing) and product surface later (projected to
  MCP/WebMCP by intentcall/mcp_flutter); modify = re-define, a tree edit,
  never a text patch.
- **Stage F — meaning tree as ECS world state (2026-08-28)**: `MeaningNode`/
  `MeaningProps`/`MeaningEdge` components + derived `MeaningIndex`;
  `act_with_project` is a thin view returning budgeted cuts (`total` +
  `truncated` green-screen); growth arm 1k→100k nodes LLM-free green;
  snapshot parity via persistent-id edge refs. Hard cuts: `StructuredDoc`
  deleted, AFM driver migrated, and the ecsly invariant landed — every
  Component registered in `AgentPlugin` (unregistered object components
  corrupt archetype column allocation); ADR-0009 components moved to
  `data_models/components.dart`.
- **`act_with_project` seam (structured editing, the "model picks a tiny move
  over the MEANING" surface)** — `src/tooling/structured_editor.dart`: ONE tool
  with a closed `FM.enum_` sub-action set; the AST is internal to a host
  materializer; the model never writes code or sees a tree.
  LLM-free-tested (`test/structured_editor_test.dart`).
  On-device proof: the tiny 2-4k model that FAILED the six-tool surface now
  builds a `dart run main.dart -> exit=0` game by picking only moves.
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
| 4 | 20-task coding suite | Ran; results honest but claim-defining number low — see [results_phase4.md](archive/results_phase4.md) and [plan_fair_pi_comparison.md](plan_fair_pi_comparison.md) for why columns weren't comparable (C1/C2/C3) |
| 5 | Concurrency gating | **Done** — `Model.maxInFlight`, per-model agency gating, `_spawn` battle-tested under serial AFM. Follow-up: scale `taskTimeout` with queue depth |
| 6 | Snapshot/restore | Open — REPL prototype only |

## Stage I — measurement & stewardship (2026-08-28)

Durable decisions extracted to [ADR 0018](../../../../docs/decisions/0018_meaning_view_zoom_projection_context_ownership.md); full analysis in [results_stage_i.md](results_stage_i.md).

- **I1/I2 — matrix + zoom finding**: the AFM context overflow (12,055 tokens)
  was the feedback channel, not the tree: move acks carried whole-tree cuts.
  Fix = the meaning view cut IS a ray projection with a closed zoom
  vocabulary (`point`/`local`/`region`/`summary`); move acks zoom to `point`
  (O(1) feedback), `list` zooms out, summary structuralizes/destructurizes.
  Ray-cast hits are SEEDS (expand by zoom radius). Same tree, same law, any
  domain — and strategies can differ per actor (mover/overseer).
- **Meaning-executor arm green scripted**: `intent_02` builds the bookmark
  executor through 24 tiny meaning moves, passes the SAME real-dart intents
  oracle as `intent_01`'s single big write; interpreter ⇄ materialized Dart
  pinned by PARITY + FAILURE-PATH PARITY tests (a real divergence bug found
  by the AFM run is now fixed and pinned).
- **I3 — AFM re-measure, honest FAIL recorded**: channel proven (100+ moves,
  materialization, self-verification); premature completion recovered by the
  mechanical verifier loop; actionable errors (`op id` in failures) drove
  `set_prop` self-repair; final blocker = append-only accretion across
  retries. Logs in `benchmark/runs/intent_closure_afm_run*.log`; analysis in
  `results_stage_i.md`. Next levers recorded (macros / compaction /
  overseer-actor repair), not built.
- **I4 — prose host #2 green**: sentence → meaning-tree outline (kind
  `section`) → facet-indexed fill beats → `evidence` tier (`passed: null` by
  construction). Same one-tool surface, same projection law.
- Suite: 22 tasks scripted green; 281 package tests passing.

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
- ~~Migrate/delete legacy manual-schedule tests (sleep + second-pass
  crutch)~~ — done 2026-09-01 (B5): `harness_headless_tools_test.dart`
  deleted; unique routing coverage ported to `test/handler_routing_test.dart`
  (`runUntilIdle` path).
- ~~Collapse overlapping edit paths (`patch_file` / `tree_patch` /
  `structured_editor`): fold into registry-truth surfaces once J1 macros
  replace their benchmark role; delete~~ — done 2026-09-01 (B4):
  `tree_patch`/`patch_tool`/`transform_flow`/`ops_handler` deleted from lib/
  + barrels (see Landed, 2026-09-01).
- ~~Delete bisection probes (`tool/probe_*.dart`, `benchmark/debug_*.dart`)
  after extracting lessons into checks/tests~~ — done 2026-08-25 (A7): probes
  deleted; lessons survive in `test/run_until_idle_tool_race_test.dart` and
  the `expectIdle` helper (`test/support/agent_harness_support.dart`).
- Fold `discussion.md` into ADRs — done via ADR 0009; discussion.md is now an
  archive of the design conversation (threads/beats/projection theory).

## 2026-09-01 (later session) — P-series: bridge fix, overseer, host seams

Landed (detail + measured tables in [results_stage_p.md](results_stage_p.md);
forward plan updated in PLAN.md §P):

- **P1** — AFM bridge generation-cancel contract (`xs_fm_cancel`,
  per-generation callback gating, generation ids on payloads, ABI version
  stale-dylib detection, structured timeout errors). The first post-B1
  pass@3 set completed: intent_03 0/3, ZERO bridge crashes / overflows.
  26/26 Swift bridge tests incl. live sessions.
- **P2** — J7 overseer actor (`lib/src/tooling/overseer.dart`): summary-zoom
  brief + closed approve/repair/escalate vocabulary + one repair cycle
  (monotonic allowance widening in RunGradedGoalPolicy). Scripted repair
  test green through the real driver; on-device intent_03 still 0/3
  (honest FAIL, classified).
- **P3 (revised)** — `JailWriteGateway` host write policy (apply/review +
  unified diffs + host approval; NO model-visible parameter — the mission's
  `writeMode` param was rejected in law review) + jailed read-only
  `git_status`/`git_diff` + write-gate audit in run logs.
- **P5** — snapshot exclusions make a restored world idle-resumable
  (budgets persist, in-flight state does not); restart-survival test;
  `coding_agent.dart --session/--resume`.
- **P6** — `coding_agent.dart --json` NDJSON transport (host-side handler
  telemetry; schema in pipeline_coding.md).

Practices:
1. The law wins over mission text: P3's model-visible writeMode was caught
   in re-review and replaced with a host-side gate.
2. Callback-after-delete crash classes are closed by CONTRACT (cancel
   before teardown + generation-id dispatch), not by hoping drains win
   races.
3. Escalation allowances widen monotonically (base × (1 + cycles)); no
   budget ever resets except via `openFreshDecision` for host-injected
   decisions.


## Stage M/N — delegation surface + live squad (2026-09-02, LANDED)

**Stage M — delegation surface.** (M0/D8) The default coding oracle is the
WORKSPACE CONVENTION, resolved mechanically (`resolveWorkspaceCheck`): Dart
package with tests → `dart test`; without tests → `dart analyze`; bare
`main.dart` → `dart run main.dart`; nothing resolvable → honest exit(64).
`--check <command>` overrides. Hardcoded per-task checkers are gone; the
criterion is part of the goal vector (ADR 0009), the executor is generic
`RunGoalSpec`. (M1) pi delegates a2a via `coding_agent.dart --json --backend
open_router`; first delegation PASSED end-to-end (delegated_calc) and caught
TWO integration bugs: the actor was spawned with a random `ModelId.create()`
unresolvable by the router (`initRuntime` throws → the actor NEVER
generated), and the runner overwrote the host router with an empty one
(escalation + capacity silently degraded). Both fixed; evidence:
`benchmark/runs/delegation_m1_evidence.md`. (M2) `tool/mine_delegations.sh` —
LLM-free git-history replay miner → delegation manifest JSONL.

**Stage N — the live squad.** (N1) `analyze_board.dart`: parses
`dart analyze --format=machine` → file-disjoint board tasks with mechanical
criteria — the problems-discovery artifact. (N2) `squad_driver.dart`:
multi-actor, one shared workspace, per-file single-writer (`FileLockTable` +
per-actor gateways; cross-owner writes rejected BEFORE the gate), per-actor
run-graded verification (`RunGoalSpec.commandByRegistry`, stamps ONLY the
pending actor), verification runs as a REGISTERED task so `canSleep()` waits
for pending verdicts (the P5 flake + squad 'no verdict stamped' race). (N3)
`harnessd` — the harness as a long-lived ACP agent (`HarnessAcpBackend` over
`dart_acp_toolkit`): sessions = threads, world snapshot per turn, D8
convention oracle. (N4) pi joined LIVE over raw stdio JSON-RPC: streamed
tool_call_updates + verdict round-trip. First live task FAILED honestly —
deepseek-v4-flash exploration loop (27 decisions, 50 rounds, never wrote) —
traced to FOUR cut defects, not the model.

**ADR 0020 — the cut is a composed document.** (N5) `CutComposition`: typed
slots (goal non-evictable + input-gated, map, observations with dedup +
drop-empty + capacity + chronological render, lastVerdict); the codec renders
slots verbatim and never re-ranks; unfilled required slots are named
`CutViolation`s — the INPUT GATE (never dispatched to the model). Conformance
suite 7/7 (`cut_composition_test.dart`). **Live before/after**: the N4
failure task re-run — 27→8 decisions, FAIL→PASS, 10.7k tokens,
goal-in-cut every decision. (N5b) `WorkspaceMapProvider` — fs-as-graph v1:
bounded tree, skip-list, test→subject links (honest `MISSING` annotation),
`+N more` overflow absences, cached per root stat; feeds the non-evictable
`map` slot. Live second delegation PASS at 7 decisions / 9.9k tokens. (N5c)
Roles as data (model ≠ actor): `AgentRole` + per-registry compositions
(`compositionByRegistry`); `roles_test.dart` — two roles on ONE model class,
per-role cuts and prompts. (N5d) a2a columns: per-actor `decisions` +
`projectionTokens` on every squad row. (M2b) `tool/seed_delegation.sh` —
parent-commit jail seeder, validated.

**dart_acp_toolkit (IntentCall repo) — permission round-trip + concurrency
fix.** (1) `AcpPermissionRequesting` interface: backends that implement it
get a client-permission requester attached at server startup
(`session/request_permission` round-trip). (2) CONCURRENCY FIX: the input
loop awaited `_handleMessage` inline, so a permission RESPONSE (or
`session/cancel`) arriving mid-prompt could never be read — the round-trip
deadlocked and cancel was dead code. Responses now route out-of-band and
dispatch is concurrent (`_handleMessageSafe`). Test:
`test/permission_roundtrip_test.dart`. Harness side: `HarnessAcpBackend`
implements the interface and wires the write gate in `review` mode — every
write asks the client (pi/human approves diffs; no git tools needed).

**AFM reliability (P1 closure, three layers).** (1) ABI v2 cancel contract
(Swift `GenerationState` queue-gated callbacks, Dart cancels BEFORE teardown)
— landed earlier. (2) NEW: pre-flight context budget in
`AppleFoundationNativeClient` (`maxContextTokens`, default 3800) — an
over-window request is rejected with the NAMED `context_window_exceeded`
failure before the bridge is called (the recorded VM crash was preceded by
'Exceeded model context window size'). (3) Swift maps context-window errors
to the same named code (belt-and-suspenders; needs a macOS bridge-test run
for verification).


---

## R7 — edit-as-re-derivation (landed 2026-09-03; ADR 0023)

Extracted from the living PLAN; the forward work is the production path in
[PLAN.md](PLAN.md). Full rows: [results_r7.md](results_r7.md); transcript:
`benchmark/runs/r7_daemon_transcript.txt`.

- **R7b — span-edit materializer.** `span_editor.dart` in the
  dart_meaning host: ONE tool (`edit_symbol`), closed enum
  (`replace_member_body` / `insert_member` via the R6 compiler's public
  `compileOpChainBody`, `apply_executable` pack-fed with the built-in
  lexical `rename_symbol` expanding over the refs frontier — never a core
  verb, the B4 lesson). Three host-enforced fences (expressiveness /
  ORACLE COVERAGE / integration) bounce as named data before generation;
  atomic batches with lock pre-check and in-memory revert; failure
  attribution (revert only what the move caused). Gate: multi-file change,
  zero `read`/`write` in registry AND beats. Write demotion: the run-graded
  fs arm is LEGACY-HOST-ONLY. Perf lesson: the verify baseline is a WORLD
  RESOURCE (`SpanVerifyBaseline` — one oracle run per state change),
  post-analyze scoped to touched files, per-phase timings on every outcome
  (a 2-file rename applies+verifies in 649 ms).
- **R7c — daemon holds the world.** Sessions keyed per workspace; the
  meaning tree is NEVER snapshotted (the codec excludes Meaning components
  at capture — the 18s restore finding resolved by re-derivation);
  mechanical `refresh` tick per prompt; `loadSession` real (restore from
  `.dart_tool/harnessd_store`); `requestPermission` deny-by-default;
  `cancelSession` real (flag observed at the turn boundary); escalation
  capped (`min(3+rounds, 9)`); unique tool-call ids; tool RESULTS streamed
  over ACP. Plus the meaning-profile surface in `runCodingAgentOnce` (the
  actor always gets its first session) and the flutter-package fix in
  `resolveWorkspaceCheck`.
- **TASK 3 — pi through the daemon.** The pi driver
  (`benchmark/pi_driver/run_r7_daemon_gate.mjs`) + the interactive
  extension (`r7_harnessd_extension.ts`): pi with ONLY the five
  daemon-backed tools; scripted mover (the gate measures the surface).
  Gate PASS: scan → zoom → impact → rename (private symbol, `flutter
  test` green) → verify, transcript committed. Friction recorded: a
  silent client is DENIED by the approver — deny-by-default enforced
  itself; the client must answer `session/request_permission`.
- **R7d — pack-fed edits.** `EditExecutableWire` in
  `agentic_executables_wire` (zero-dep; unknown kinds fail LOUDLY);
  `registerPackExecutable` on the materializer; the worked example
  `dart/fix_loop_bound` lands at ZERO authored tokens (the op-chain
  travels with the pack).
