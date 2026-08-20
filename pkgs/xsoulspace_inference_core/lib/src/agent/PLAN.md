# Agent Harness — Improvement Plan

> Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness.
> Thesis: harness = intelligence amplifier; model = replaceable reasoning primitive.

## Phase 0 — Benchmark harness (measure first)
- Scripted tasks vs `MockGenerationHandler`.
- Record: tokens/decision, LLM calls/task, context growth, task success, thread prune/merge.
- Context-budget assertion: projection over budget fails the benchmark.

## Phase 1 — Cinematic projection (the intelligence) ✅
- `ProjectionSystem` takes a token budget → relevance-ranked, thread/beat-aware,
  green-screen-explicit, tool-format-aware `Situation`.
- Enforce budget at projection time.
- `Situation` now carries the projected `contextFragments`, `explicitAbsences`,
  `toolRegistryName`, `tokensUsed`, `tokenBudget`, `truncated`.
- Resources: `ProjectionBudget`, `ProjectionPolicy`.
- `actorActSystem` sends ONLY the projected cut to the model (never raw memory).

## Phase 2 — Bounded memory via mechanical delegation
- Harness owns history. Mechanical systems compact/summarize/prune into Props.
- `ActorRuntimeMemories` becomes a projected view, not an append-only log.

## Phase 3 — Agency policy + escalation
- Prioritize which actor/decision gets agency (urgency, cost, dependency).
- `EscalationRequest`: low-confidence local model hands a beat to a bigger
  remote model, folds result back.

## Phase 4 — Wire threads/multiplayer into projection
- Projection follows the graph: shared/private/derived threads. a2a / a2h / a2h2a.

## Phase 5 — AST as a tool seam (later)
- Add as a capability/tool behind `ToolRegistry`, not a core change.