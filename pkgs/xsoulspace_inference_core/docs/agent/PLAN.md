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

## Phase 3 — Streaming through FFI bridge

Apple Foundation streaming wired through the native bridge into
`ActorGenerateStreamEvent` (the harness plumbing already exists). Measure
time-to-first-token on-device. Unblocks coding-agent UX: no more silent 30s
waits on file writes.

## Phase 4 — 20-task coding suite vs pi

Fixed task set (file edit, multi-file refactor, search-then-edit, tool chains)
with deterministic pass/fail checks. Run against real AFM; run the same tasks
through pi with a comparable hosted model. Output: pass rate, tokens/task,
wall-clock, $/task. This is where the efficiency claim gets its numbers.

## Phase 5 — Concurrency gating in AgencyPolicy

AFM serializes requests on-device. Add backend-declared max-in-flight to
`AgencyPolicy`; agency grants gate on it. Prevents invisible queueing and
timeout-sweeper false positives when many actors act concurrently.

## Phase 6 — Snapshot/restore + baseline table

World snapshot/restore (threads, beats, facet-index rebuild) so the CLI
survives restarts — required for daily-driver parity with pi. Then publish the
final comparison table from Phase 4 as the headline artifact.

## Later / parked

- **Angle-of-view / scale tiers** — projections queryable at a scale (beat,
  thread, subset) so a ray can coarsen, not just narrow.
- **AST as a tool seam** — add as a capability/tool behind `ToolRegistry`, not
  a core change.
