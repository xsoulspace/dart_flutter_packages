# ADR 0009 — Goals as verifiable vectors; plans as derived projections

**Status:** Accepted
**Date:** 2026-08
**North Star impact:** `clarifies` — extends the "what this subsection owns"
list (Projection, Agency discipline) with a future-tense projection class; the
objective, non-goals, and competitive claim are unchanged (strengthened).

## Context

The harness has a rich past (beats), a rich present (projected situations),
and almost no future representation:

| Concept | Reality before this ADR | Problem |
| --- | --- | --- |
| `Goal` | `{String text}` on an actor | Dead weight — no criteria, no lifecycle |
| `GoalLink` | Optional entity pointer on threads | A tag; nothing can reason about progress |
| `OpenDecision` | Ephemeral gate for one LLM call | Knows *that* a decision is needed, not which goal/step it serves or how it will be judged |
| Planning | Lives entirely inside the model's head, per call | Re-purchased with tokens every decision; invisible to the harness |

Planning was therefore the last thing still done the conversation-log way:
re-derived from scratch inside a tiny context window on every call. That is
inconsistent with the harness thesis ("the harness does the heavy lifting;
context stays bounded and derived").

Observation driving the design: memory was already removed as a primitive —
beats are source of truth, memory is a re-derivable projection. Planning
suffers from the identical disease memory had, and yields to the identical
cure.

## Decision

Three commitments:

### 1. Goal = vector + verification predicates (durable facts)

A `Goal` is an entity carrying direction text, machine-runnable success
criteria where possible (**tool-callable predicates** behind seam 3:
run-tests, diff-check, AST-shape check, scripted invariant), explicit
unverifiable remainder, owner, and lifecycle status
(`active | achieved | abandoned`). A goal that cannot state at least one
predicate is flagged as a wish, not silently accepted.

### 2. Plan steps = first-class entities on a verifiability spectrum

Steps are **not beats**. Beats record what happened (evidence); steps record
what is intended and whether it held. Each step entity carries:

- `goalLink`, `dependsOn[]`, `threadId`
- claim (what would be true if done)
- `verificationKind`: `mechanical` (predicate tool, never touches an LLM) |
  `observable` (read a prop / confirm state) | `open` (genuinely needs agency)
- `status`: `open | blocked | verified | failed | superseded`
- confidence, updated mechanically as verification evidence lands
- links to the **evidence beats** produced by verification runs

Superseded steps remain queryable (like pruned threads): revision history is
preserved for free, plans never go stale because no plan document exists.

Every `OpenDecision` gains an optional `stepId` backlink: **agency grants
carry their acceptance criteria in-frame**. Vague prompts become graded
problems.

### 3. The plan is a derived projection — never stored

"Project a plan I'm entitled to": a second projection class alongside the
situation cut. It traverses **explicit `goalLink`/`dependsOn` edges**
(deliberately not keyword rays — this sidesteps the Phase 4b keyword-drift
failure mode for plan *discovery*), and emits only the frontier: unblocked
steps within budget, green-screen for everything else. Token-budgeted like
any cut; flatness applies.

Agency-vs-mechanical extends to the future tense: only `open` steps ever
become `OpenDecision`s; `mechanical` steps execute and verify without an LLM.

### Decomposition is one agentic act

Decomposition is an `OpenDecision` of kind "decompose" (one call per goal,
amortized — possibly the one place a stronger tier earns its tokens).
Everything downstream — execution ordering, verification, frontier
recomputation, status flips — is mechanical graph logic, testable with mock
generators per ADR 0003.

## What this is not

- **Not a planner subsystem.** No replanning policy engine, no plan schema
  versioning, no planner agent. Rule: steps in, projection out, checks fail
  loudly. If a mechanism starts needing its own policy engine, stop — that is
  drift (see North Star gravity).
- **Not pushed into ecsly-the-foundation.** Goal/Step semantics are narrative
  concepts; they belong in the harness as plain data. ecsly stays domain-free.
- **Not math special-casing.** A proof checker is just another verifier
  `ToolDef`; math goals work with zero core change if a checker mod enters
  through seam 3 later.
- **Not a replacement for Phase 4b.** Execution-context recall for a step
  (which beats the actor needs to *execute* it) is still ray-based and still
  drift-exposed. Phase 4b machinery remains load-bearing; its scope narrows to
  execution-context quality.

## Relationship to existing work

- `coding_suite_afm.dart`'s mechanical checker feedback loop is exactly this
  pattern, hardcoded per benchmark. Generalizing it into `Goal.successCriteria`
  makes the coding suite a special case of the harness.
- Phase 6 note: `_save/_load` in `apple_foundation/bin/agent.dart` is a local
  REPL prototype, **not** the Phase 6 deliverable (ecsly_serializable +
  universal_storage persistence, facet rebuild from restored beats,
  crash-mid-decision restore, byte-match oracle). Step/goal entities must be
  included in the real snapshot contract.

## Consequences

- Tokens-per-task improves twice: no in-window plan re-derivation, plus
  mechanical execution/verification of verifiable steps.
- Every published benchmark column gains a decompose/verify provenance
  (escalation-rate metric extended with a "mechanical-step share" metric: the
  fraction of completed work that never touched an LLM — a direct measure of
  the agency-discipline claim).
- Smallest falsifying experiment: take one coding-suite task, express its
  steps as goal-linked entities with checker-based criteria, run the loop with
  mechanical steps skipping the LLM, measure the tokens/task delta.
  **Executed 2026-08 across all 20 suite tasks: −39% LLM calls, −24%
  tokens/task, equal pass rate. Not noise — the mechanism survives.**
  See [results](../../xsoulspace_inference_core/docs/agent/results_plan_falsification.md).
  Known gap before production shape: the experiment's frontier policy reads
  the workspace fs directly; predicates must become verifier-tool beats to
  keep policies pure.

## References

- [North Star](../../pkgs/xsoulspace_inference_core/docs/north_star_agentic_harness.mdx)
- ADR 0003 (LLM-free evaluation), ADR 0004 (causal coupling — reused for
  decomposition fidelity), ADR 0007 (seam 3 for verifier tools)
- [Fair pi comparison](../../pkgs/xsoulspace_inference_core/docs/agent/plan_fair_pi_comparison.md)
  — C1 fix determines whether hosted columns can even measure tokens honestly
  before/after this lands.
