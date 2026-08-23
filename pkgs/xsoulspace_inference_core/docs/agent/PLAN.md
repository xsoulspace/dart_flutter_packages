# Agent Harness — Improvement Plan

> Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness.
> Thesis: harness = intelligence amplifier; model = replaceable reasoning primitive.

The working model is a **living, multi-linear game world**, not a conversation
log. Memory was removed as a primitive: there is no per-actor fragment list and
no compaction policy. An actor's reality _is_ the cut (`Situation`) you hand it;
memory is just one flavor of projection.

Phases below mirror the North Star table. Status: `done` / `active` / `next`.

## Done

- **Cinematic projection (the intelligence).** `projectSituationSystem` takes a
  token budget → relevance-ranked, thread-aware, green-screen-explicit
  `Situation`. Budget enforced at projection time; system prompt + tool schemas
  counted against the real budget.
- **Graph-native, memory removed.** Beats are indexed into a `FacetIndex`
  (keyword → beats). Projection is a ray (keyword hits ∪ actor's `ActorThreads`),
  not a scan of a per-actor memory list. Summary is a first-class beat kind
  (`MemorySummary`), produced only by the deliberate `summarizeThread` transform.
- **Multi-thread projection.** Rays traverse _all_ of an actor's threads;
  `ThreadStatus` (pruned/merged/archived) filters entry; `ThreadVisibility`
  restricts who may see what; `PrivateToActor` beats never enter another
  actor's cut — including via keyword hits. Pruned threads deindex their beats.
- **Targeted decisions.** `OpenDecision.threadId` routes beat attachment and
  identity seeding to a specific thread.
- **Failure guarantees.** Throwing/hanging tools produce error results after
  `AgencyPolicy.taskTimeout`; missing/crashed handlers fail fast; failed
  responses retry up to `AgencyPolicy.maxRetries`; a timeout sweeper frees
  actors stuck in `AwaitingResponse`. The loop can never hang on a bad backend.
- **Real escalation tiers.** `Model.tier` ranks models; escalation picks the
  lowest strictly-higher tier, never an arbitrary map order.
- **Collision-free IDs.** `TaskId`/`AgentId`/`ModelId` use timestamp +
  monotonic counter.
- **Single tool-result path.** All tool results flow
  `ToolCallEvent → toolExecutionSystem → ToolResultEvent → beats`. No duplicate
  recording from handler responses.
- **CLI/server ergonomics.** `HarnessLoop.runUntilIdle({maxTicks})` drives all
  schedules until idle — the headless entry point. Jailed fs tools
  (`fsTools(FsToolsRoot(...))`) for VM hosts.
- **Metrics machine.** `MetricsCollector` + `MetricsReport`: tokens/beats/tools
  trends, dangling-tool detection. Wired into `ScenarioRunner` and
  `harness_benchmark.dart`.
- **Scenario stress-testing.** `ScenarioRunner` drives the real loop against a
  real model over multi-actor, tool-using scenarios.
  CLI: `apple_foundation/example/lib/main_stress_cli.dart`.
  See `docs/scenario_stress_testing.mdx`.
- **Idle-detection correctness (runUntilIdle race, fixed 2026-08).** Two
  related bugs made `HarnessLoop.runUntilIdle` exit while async tool work was
  still in flight, stranding results in event channels:

  1. Response-carried `ToolCallEvent`s had no `taskId`, so the in-flight tool
     was invisible to `canSleep()` (which checks `TaskRegistryResource`).
     Fix: `processResponsesSystem` registers a `TaskHandle` per dispatched
     call; `toolExecutionSystem` resolves it on completion.
  2. A completed tool sends its `ToolResultEvent` and resolves its task in
     the same microtask — leaving a window where the registry is empty but
     the result still needs one more `Mechanical` pass to become a beat.
     Fix: `canSleep()` also treats unconsumed `ToolResultEvent`s as pending
     work.

  Regression: `test/run_until_idle_tool_race_test.dart`. The manual-schedule
  tests never caught this because they hardcode a sleep + second Mechanical
  pass; only the production `runUntilIdle` path exposed it. See "Detecting
  idle-race bugs" below.

## Phase 1 — Docs & North Star (done)

Claims separated from proofs in `docs/north_star_agentic_harness.mdx`;
competitive claim made explicit and falsifiable; this plan restructured into
measurable phases.

## Phase 2 — Long-horizon scaling benchmark (done)

Scripted 1,000-decision run with mock handlers (`benchmark/long_horizon_benchmark.dart`):

- **tokens/decision flat**: early=241, late=258 → **flatness 1.07x** while the
  beat graph grew to 1,000 beats and the facet index to ~926 keywords.
- **latency sublinear**: 0.81ms → 1.55ms per decision (**1.92x**) while beats
  grew 1000x.
- **budget never exceeded.**

Gated in CI by `test/long_horizon_test.dart` (300 decisions, same assertions).
CLI: `dart run benchmark/long_horizon_benchmark.dart [decisions]` — non-zero
exit on failure.

## Phase 3 — Streaming through FFI bridge (done)

`xs_fm_generate_stream_async` added to the Swift bridge: AFM
`streamResponse` snapshots are emitted as `\"delta\"` chunks through a new
stream callback; `done_cb` still fires once with the final text. Structured
output requests fall back to blocking respond (framework delivers structured
content atomically).

Dart side: new `StreamCbNative` binding, `AppleFoundationNativeClient` now
implements `StructuredTextStreamingInferenceClient` (`streamStructuredText`),
deltas flow as `InferenceStructuredTextStreamEvent.partialOutput`. The harness
plumbing downstream (`ActorGenerateStreamEvent` → `StreamingBeat`) already
existed.

**Measured on hardware**: TTFT ~8.3s for a cold first call (model warm-up
dominates), deltas stream correctly with multi-line output, final result
matches streamed text. Smoke: `dart run bin/stream_smoke.dart`.

Also fixed: `jsonEscaped` helper emitted raw control characters into JSON
(newlines broke Dart's decoder) — replaced with a JSONEncoder-based escaping
that round-trips correctly.

## Phase 4 — 20-task coding suite vs pi

Fixed task set (file edit, multi-file refactor, search-then-edit, tool chains)
with deterministic pass/fail checks. Run against real AFM; run the same tasks
through pi driving the harness as an MCP/ACP server (ADR 0007 §3) with a
comparable hosted model. Output: pass rate, tokens/task, wall-clock, $/task.
This is where the efficiency claim gets its numbers.

Additions binding via ADR 0007:

- **Escalation-rate metric** per task class — if AFM escalates often, the
tiny-model claim is failing quietly; publish it next to pass rates.
- **Extensibility ledger** — the host CLI logs every core change it needs;
three entries against the same seam trigger a design conversation (ADR 0007 §4).
- **Tool-surface gap closure** for coding tasks: search/grep, jailed shell,
edit-with-diff-verification, per-tool human-confirmation gates. Each enters
via seam 3 (`ToolDef`); none change core.

## Phase 4b — Reduction-fidelity evaluation (structurification)

Summarization exists only as a *reduction transform*: long text → classify →
beats with facets. Its quality is measured deterministically with ADR 0004's
machinery, no embedding judge:

- **Reduction fidelity** = the reduced beat still triggers the correct ray and
causally gates scripted success (`ContextCoupledHandler`).
- **Keyword-drift benchmark** — paraphrased/reduced beats whose keywords no
longer match future rays become invisible; measure ray recall under vocabulary
drift. This is the known failure mode of keyword-facet retrieval; it must be
measured, not assumed away.

## Phase 5 — Concurrency gating in AgencyPolicy

AFM serializes requests on-device. Add backend-declared max-in-flight to
`AgencyPolicy`; agency grants gate on it, and `taskTimeout` scales with queue
depth so the timeout sweeper stops firing false positives on serial backends.
Prevents invisible queueing when many actors act concurrently.

## Phase 5b — Seam conformance suites

Per ADR 0007 §2: policy conformance (determinism, purity canary), tool
conformance (timeout/error-shape/serialization round-trip), handler
conformance (ScriptedTurn fault matrix), projection conformance (budget
assertion at runtime in debug mode). Precedent: `universal_storage_conformance`.
Mods that break determinism fail at development time, not inside evaluations.

## Phase 6 — Snapshot/restore + baseline table

World snapshot/restore so the CLI survives restarts — required for daily-
driver parity with pi. Binding requirements in ADR 0007 §5:

- Persist beats/threads/components via `ecsly_serializable`, stored through
`universal_storage`; **rebuild** the facet index from restored beats (derived
state is never source-of-truth).
- Crash mid-decision restores to a re-opened decision, never stuck
`AwaitingResponse`.
- Golden oracle: post-restore projections byte-match pre-snapshot projections.

Then publish the final comparison table from Phase 4 as the headline artifact.

## Everyday CLI host (thin, per North Star non-goals)

REPL on `HarnessLoop.start()` + `wakeup()`: streaming deltas to the TTY (FFI
streaming exists), user input as new decisions while idle, cancel-in-flight
mapped to task cancellation + agency release (not process kill), `/situation`
inspector showing an actor's current cut, snapshot autosave, confirmation-
gated tools. The CLI stays embarrassingly thin: any need beyond snapshot +
streaming + confirmation gates is an extensibility-ledger entry, not a core
change.

## Cleanup

- Fix the 8 known-failing core tests (`fs tools path jail`, headless tool
routing, decision flow) — Phase 4 blockers; honest benchmarking needs green
baselines.
- Migrate or delete legacy manual-schedule tests (the sleep + second-pass
crutch that masked the idle-race bug; see postmortem above).
- Delete bisection probes (`tool/probe_*.dart`, `benchmark/debug_*.dart`)
after extracting durable lessons into checks/tests.
- Fold `docs/agent/discussion.md` into ADRs; keep PLAN as the only living plan.
- Make the web-vs-VM split (`fs_tools.dart`) enforceable by lint/separate
barrel instead of a comment.

## Later / parked

- **Angle-of-view / scale tiers** — projections queryable at a scale (beat,
  thread, subset) so a ray can coarsen, not just narrow.
- **AST as a tool seam** — add as a capability/tool behind `ToolRegistry`, not
  a core change.

## Detecting idle-race bugs (postmortem → practice)

The runUntilIdle race (see Done) took days because three layers each looked
innocent in isolation: the event channel passed its own tests, the systems
passed manual-schedule tests, and the loop's `canSleep()` was _almost_ right.
Practices adopted so the next one surfaces in minutes:

1. **Invariant: "idle ⇒ nothing stranded."** `canSleep()` must be provable
   from world state alone. Any new async path that sends an event or spawns
   work MUST either register a task or be covered by the channel check.
   Review checklist item for every new event-producing system.
2. **Production-path tests only.** Manual schedule-stepping tests
   (`runSchedule` + sleeps) mask timing races. New harness behavior tests
   must go through `HarnessLoop.runUntilIdle` / `tickForDebug`. The sleep+
   second-pass crutch in older tests is legacy — don't copy it.
3. **Stranded-event assertion.** After `runUntilIdle`, all harness channels
   (`ActorGenerateRequest/Response`, `ToolCallEvent`, `ToolResultEvent`,
   stream events) must be empty. Cheap to assert; catches any future
   "loop exited early" bug at the exact failing tick. Candidate for a shared
   `expectIdle(world)` test helper if it recurs.
4. **Bisection probes over code reading.** When data is lost between producer
   and consumer, instrument the boundary first (drain counts per stage),
   read code only after the loss point is localized to one hop.
