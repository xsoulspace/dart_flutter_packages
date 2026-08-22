# ADR 0004: Intelligence-grade harness evaluation (exact cuts, decoys, causal coupling)

- Status: Accepted
- Date: 2026-08-23
- North Star impact: `clarifies`
- Amends: [0003](0003_llm_free_harness_evaluation.md)

## Context

ADR 0003 delivered discipline metrics: the harness is deterministic,
fault-tolerant, privacy-preserving, and bounded in context cost. But its
oracle scoring had three honesty gaps that blocked any "intelligence" claim:

1. **Residue scoring** — precision/recall were computed over post-run world
   state, not the actual per-decision cut.
2. **Keyword self-agreement** — the oracle's keywords matched the projector's
   keyword mechanism, so recall ≈ 1.0 was near-tautological; it validated
   plumbing, not retrieval discrimination.
3. **No causal link** — nothing connected "the harness projected context X"
   to "the agent then succeeded." Ablations measured policy *cost*, not
   *benefit*.

## Decision

Three upgrades, all still LLM-free and deterministic:

1. **Exact per-decision cut capture.** `ScenarioRunner` snapshots the
   projected beat texts (`DecisionMetrics.projectedTexts`) at projection
   time, inside the decision window. Oracle scoring uses the true cut;
   residue remains only as a fallback for legacy metrics.
2. **Adversarial decoy oracles.** `DecisionOracle.decoyTerms` marks prompt
   words that also appear in planted decoy beats ("parser bug" vs "parser
   museum"). Beats matching only decoys count against precision — precision
   now measures *discrimination*, not self-agreement.
3. **Causal task-coupling.** `ContextCoupledHandler` answers correctly only
   if the projection contained a required phrase; otherwise it fails
   deterministically (`contextSufficiencyRate`). Projection quality → task
   success becomes a measurable causal chain with zero model calls.

## Consequences

- Truthful claims now extend to: *"projection precision/recall are exact and
  decoy-resistant"* and *"context sufficiency causally gates scripted task
  success."*
- Remaining honest limit: scripted actors still cannot demonstrate that the
  harness helps a *real* brain; they bound it. Agency precision stays
  unmeasurable until mechanical decision creation exists (e.g., tool results
  opening continuation decisions).
- `DecisionMetrics` gained an optional field; older constructors are
  source-compatible.

## Non-goals

No embedding judge (nondeterministic); no LLM scoring; no change to
production systems — all additions live under `testing/`.
