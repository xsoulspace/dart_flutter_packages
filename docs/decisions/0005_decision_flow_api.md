# ADR 0005: DecisionFlow — a public, composable decision-creation API

- Status: Accepted
- Date: 2026-08-23
- North Star impact: `clarifies`
- Builds on: [0003](0003_llm_free_harness_evaluation.md), [0004](0004_intelligence_grade_harness_evaluation.md)

## Context

The harness formula is `Agent = G ∘ F`, where `F : State → State` is the
deterministic harness and `G` the generative model. ADR 0004 made projection
quality measurable, but **agency precision stayed unmeasurable**: decisions
entered the world only via host injection or the hardcoded ReAct continuation
inside `processToolResultsSystem`. Nobody could answer "why did this actor
wake up?" without reading system internals, and no metric could attribute a
wasted model call to the policy that caused it.

For extremely small models (2–4k context, on-device), every decision matters
twice: it costs tokens AND it reshapes the next Situation. Decision creation
must become (a) public and programmable, (b) attributable per policy,
(c) evaluable — including how each decision changes projections.

## Decision

### 1. `DecisionPolicy` — pure observation → draft

```dart
abstract class DecisionPolicy {
  String get name;
  /// Observe the world; return a decision to open on [ctx.actor], or null.
  /// MUST be deterministic and side-effect free.
  DecisionDraft? evaluate(DecisionContext ctx);
}
```

`DecisionContext` exposes read-only accessors over the world (actor
components, last tool result, tick, co-present actors). Policies never
mutate; a single mechanical system (`decisionFlowSystem`) collects drafts and
applies them. This keeps evaluation trivial: fixture state in, draft out.

### 2. Combinators — composition over inheritance

```dart
final flow = DecisionFlow([
  onToolResult().thenOpen(prompt: 'Tool result received. Continue.'),
  onError().thenRetry(),
  when((c) => c.has<Goal>() && !c.has<OpenDecision>())
      .thenOpen(prompt: 'Pursue your goal'),
  everyNTicks(600).thenDream('Review progress; consider delegating'),
]);
```

Builders: `onToolResult()`, `onError()`, `when(predicate)`,
`everyNTicks(n)`. Effects: `.thenOpen(...)`, `.thenRetry()`,
`.thenPrompt(...)`, `.thenDream(...)` (see §5), `.shareWith(actorIds)`
(see §6). Flows are immutable data — golden-ledger diffs reveal routing
changes.

### 3. `DecisionOrigin` — attribution

Every mechanically created decision carries `DecisionOrigin(policyName)`.
Agency precision becomes per-policy:

```
precision(policy p) = decisions_from_p_that_produced_nontrivial_world_delta
                    / decisions_created_by_p
```

Wired into `MetricsCollector` / `ScenarioMetrics`.

### 4. Migration

The hardcoded ReAct block moves to the default flow:
`DecisionFlow.defaultReAct()` = `onToolResult().thenOpen(...)`, bounded by
the existing `maxToolRounds`. Behavior is preserved; `tool_continuation_test.dart`
is the regression gate.

### 5. Deferred thinking ("dreaming")

Small models sometimes need a *deliberate* second pass with richer context.
`.thenDream(prompt)` opens a decision tagged `DeferredThinking`, which the
projection system treats as "expand the cut" (raise beat cap for that turn).
It remains an ordinary decision — same loop, no special machinery — so it
stays deterministic and measurable like any other agency spend.

### 6. Actor-to-actor sharing

Policies may attach `.shareWith(agentIds)` to a draft; the applying system
writes `AddressedTo` beats or duplicates the originating beat into the target
actors' threads under existing `ThreadVisibility` rules. Sharing is therefore
just decision creation plus graph writes — already invariant-checked
(ADR 0003).

## Consequences

- Agency precision becomes a first-class, per-policy metric.
- Decision routing is developer-visible data, not buried control flow.
- All prior evals (exact cuts, decoys, coupling) apply unchanged to
  policy-created decisions; new evals can assert "policy X fires iff trigger
  Y" as pure-function tests.
- Risk: predicate misuse (nondeterminism, hidden I/O). Mitigated by
  convention + review; runtime enforcement is future work.

## Non-goals

No scheduler/CRON daemon; no cross-world policies; no LLM-in-policy (policies
are mechanical by definition — dreaming is a *request* for more model thought,
not model-driven routing).
