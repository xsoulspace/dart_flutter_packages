# ADR 0003: LLM-free harness evaluation (scripted actors, oracles, invariants)

- Status: Accepted
- Date: 2026-08-23
- North Star impact: `clarifies`

## Context

The agent harness (`HarnessLoop` + schedules) is claimed to be efficient and
"intelligent" (sparse agency, tiny projections, coherent thread graph), but
those claims were only checked ad hoc against mock handlers in tests. Real-LLM
evals are slow, nondeterministic, and cannot isolate harness regressions from
model noise.

## Decision

Evaluate the **harness itself** with zero LLM calls, deterministically:

1. **Scripted handler** (`ScriptedGenerationHandler`): a `GenerationHandler`
   test double driven by declarative turns — text, tool call(s), structured
   output, streaming deltas, empty (retry path), error, throw, hang
   (timeout path). Records every request for assertions.
2. **Oracle scoring** in scenarios: each decision may declare expected tool
   calls and must-/must-not-project keywords; `ScenarioMetrics` reports
   projection precision/recall and goal completion (no retries, no dangling
   tools).
3. **Global invariants** (`checkHarnessInvariants`): asserted on any world
   state — Agency implies OpenDecision; no private beat of another actor in a
   projection; no pruned/merged/archived beat in a projection; harness event
   channels consistent.
4. **Golden ledgers**: `HarnessExecutionLedger.dump(includeTiming: false)` is
   byte-deterministic; diffing two identical runs catches behavioral drift in
   refactors.
5. **Ablation matrix** (`runAblations`): same scenario under named
   `ProjectionPolicy`/budget configs; deltas quantify what pruning,
   green-screen, and budgets actually buy.

## Consequences

- Harness regressions become CI failures with named metrics, before any model
  is in the loop.
- Token counts remain estimator-based (chars/4); thresholds inherit that
  approximation until a real tokenizer lands.
- intentcall-style registry projection and an ACP session facade remain future
  work; they are DX improvements, not prerequisites for measurement.

## Non-goals

No embedding-based relevance judge (nondeterministic); no LLM-in-loop scoring;
no compatibility layer for old mock handlers (`MockGenerationHandler` stays).
