# ADR 0018 — The meaning view is a zoom projection; context is harness-owned; the macro gate fired

- Status: Accepted
- Date: 2026-08-28
- North Star impact: `clarifies` — the meaning tree was already world state
  projected per decision (ADR 0009); Stage I added the granularity and
  ownership laws, with measurement.
- Builds on: [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0013](0013_native_tool_calling_first.md),
  [0016](0016_measure_tool_efficiency_simplify_surface.md),
  [0017](0017_ae_etl_planning_and_a2a_native.md)
- Related: `pkgs/xsoulspace_agentic_harness/lib/src/meaning/meaning_tree.dart`,
  [results_stage_i.md](../../pkgs/xsoulspace_agentic_harness/docs/agent/results_stage_i.md),
  `pkgs/xsoulspace_agentic_harness/benchmark/runs/intent_closure_afm_run*.log`

## Context

Stage I ran the bookmark-manager intent-closure loop on-device
(Apple Foundation, 4k window) four times. Failures were data:

1. **Run1 — context overflow at 12,055/4,096 tokens.** Not the tree: the
   *feedback channel*. Every move ack returned a budgeted view cut, and for a
   small tree that cut was the whole tree; the native session accumulates
   every tool result, so ~28 moves ≈ 28 tree copies.
2. **Run2 — premature completion recovered by the mechanical verifier loop**,
   but exposed a real parity bug (materialized Dart threw where the
   in-process interpreter returns errors-as-data) — fixed and pinned.
3. **Run3 — actionable errors (op ids in failures) drove `set_prop`
   self-repair**; dangling then-chains motivated host-side chain validation
   at materialize time.
4. **Run4 — honest FAIL on append-only accretion across retries** (the model
   rebuilt onto stale op ids; `no meaning executor` at oracle time).

## Decision

1. **The meaning view is a zoom projection with a closed vocabulary**:
   `meaningZoomLevels = [point, local, region, summary]` (D3 law extended to
   the view itself).
   - Move acks zoom to `point` (focus + edges only, O(1) in tree size, no
     fill) — per-move feedback no longer scales with tree size.
   - `local` = focus + 1-hop + ray-cast hits + small-tree fill (default).
   - `region` = seeds + 2-hop, no fill. `summary` = structuralize /
     destructurize (kind histogram + aggregated edges, no node details).
   - **Ray-cast hits are SEEDS**: a query hit expands its neighborhood by the
     zoom radius — relevance frontier, not a flat list.
   - Edges render with full stable handles even when the other endpoint is
     not admitted — zoom-in then zoom-out is lossless for navigation.
   - Strategies may differ per actor (mover: `point`; overseer: `summary`) —
     the zoom is a per-call knob on shared world state, the multi-actor shape.
2. **Context is harness-owned.** The projection budget law only bounds the
   harness-built prompt; a persistent native session accumulates outside it
   and can overflow regardless. The harness must own what the model sees
   (session-per-decision or host-side compaction) — experiment pending
   (plan `J2`), direction committed now.
3. **The macro gate (D3) has fired.** Move-density evidence: 24 micro-moves
   per subtask × per-round overhead ≈ the window; hand-written-write arm
   needs 1. Composite sub-actions implemented as *host programs*
   (`add_chain`, `redefine_intent` with atomic chain replacement — scoped
   repair, not general deletion) are committed as plan `J1`.
4. **Failures must localize**: op-level errors carry op ids; the materializer
   validates chains and reports problems in the ack (`validateMeaningProgram`)
   — verification moves to the earliest host moment, not one oracle
   round-trip later.

## Consequences

- Feedback cost is decoupled from tree size (growth arm still flat; now the
  *channel* is flat too).
- Accretion across retries is absorbed by scoped re-derivation (`J1`), not by
  mutation risk.
- The 4k window remains the hard wall: generality comes from
  decomposition + verification (harness), never from a longer prompt.
- Out of scope / not decided here: out-of-process intent transport (H5),
  domain materializers (stay in host packages, ADR 0015).
