# Agent Harness — Improvement Plan

> Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness.
> Thesis: harness = intelligence amplifier; model = replaceable reasoning primitive.

The working model is a **living, multi-linear game world**, not a conversation
log. Memory was removed as a primitive: there is no per-actor fragment list and
no compaction policy. An actor's reality *is* the cut (`Situation`) you hand it;
memory is just one flavor of projection.

## Done

- **Cinematic projection (the intelligence).** `ProjectionSystem` takes a token
  budget → relevance-ranked, thread/beat-aware, green-screen-explicit
  `Situation`. Budget enforced at projection time. `actorActSystem` sends ONLY
  the projected cut to the model.
- **Graph-native, memory removed.** Beats are indexed into a `FacetIndex`
  (keyword → beats). Projection is a ray (keyword hits ∪ actor's `ActorThreads`),
  not a scan of a per-actor memory list. Summary is a first-class beat kind
  (`MemorySummary`), produced only by the deliberate `summarizeThread` transform.
- **Agency policy + escalation.** Prioritized grants (urgency/dependency),
  concurrency cap, and escalation routing to a stronger model.
- **Testable without an LLM.** Every part except *write a beat* is deterministic
  graph logic, exercised with a mock handler.

## Next

1. **Scenario stress-testing (active).** `ScenarioRunner` + `ScenarioMetrics`
   + `ScenarioMetricsReporter` drive the real `HarnessLoop` against a real
   model (Apple Foundation) over multi-actor, multi-topic, tool-using
   scenarios. Entrypoint: `apple_foundation/example/lib/stress_cli.dart`.
   See `docs/scenario_stress_testing.mdx`.
2. **Metrics machine (done).** `MetricsCollector` + `MetricsReport` fold
   per-decision tool results and projections into trends (tokens/beats/tools),
   with dangling-tool detection. Wired into `ScenarioRunner`.
3. **Per-request tool isolation (done).** Each Apple Foundation `generate` owns
   its handlers under a `requestId`; Swift echoes it on `onToolCall`.
4. **Run the real hardware e2e** — execute `stress_cli.dart` on a macOS 26+
   Apple Intelligence host and iterate on the weak spots it surfaces.
5. **Wire threads/multiplayer into projection** — shared/private/derived threads,
   a2a / a2h / a2h2a. Projection follows the graph.
6. **Angle-of-view / scale tiers** — a projection should be queryable at a scale
   (`beat`, `thread`, beat subset) so a ray can coarsen, not just narrow.
7. **AST as a tool seam (later)** — add as a capability/tool behind
   `ToolRegistry`, not a core change.