# ADR 0017 — AE-ETL (agentic_executables) for raw→matrix→planning; a2a-native multi-actor as the default build path

- Status: Accepted
- Date: 2026-08-27
- North Star impact: `clarifies` — the harness is a2a-native (any actor can
  address any other; hundreds in parallel, runtime-swappable LLM,
  a2a/a2h/a2h2a). Raw→structured→planning comes from a sibling (AE), as
  **world-affordance**, never as actor-memory.
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0014](0014_composition_surface_and_discovery.md),
  [0015](0015_domains_live_in_hosts_core_stays_generic.md)
- Related (upstream): `~/xs/agentic_executables` —
  `KnowSource` → `RepoExtractor`/`SpecImportParser`/heuristic extractors →
  `CanonicalMatrix` → tiered `verify_report`.

## Context

To make an embedded coding agent that codes **as well as pi** (e.g. "build a
whole tic-tac-toe from scratch" interactively), the plan surfaced three gates:
(see `docs/agent/PLAN.md`): a run/execute tool, a persistent plan/goal loop,
and a human-as-actor ("ask the user") seam. Two design facts shape HOW to build:

1. **The system is a2a-native.** Actors are first-class, swarmable, and any
   actor can address any other (or a human). "Build a game" is naturally a
   *team*: a Planner, a Coder, a Verifier — each routing to its own model, each
   projecting the shared repo via `FacetIndex`, baton-passing through threads.
2. **"Raw unstructured → planning" already exists upstream in AE.** AE turns a
   brief/spec/repo into a `CanonicalMatrix` (features, columns) and verifies
   it tier-by-tier. We should *consume that structured view* as the plan, not
   re-implement ETL in the harness core.

Both keep the core **generic and small** (ADR 0015): the harness composes
generic shapes; domains + ETL live as hosts/affordances.

## Decision

1. **Consume AE as world-affordance, not as actor-memory.** Add to the harness
   a seam-3 `plan_from_spec` tool that (a) imports a brief via AE into a
   `CanonicalMatrix`, (b) renders that matrix as **goal + step beats**, so the
   `PlanFrontier` (ADR 0009) drives building from the AE-derived plan, (c) on
   verify consumes AE's tiered gaps (`invariant_violation` > `upstream_blocker`)
   as the next decision. See `bin/plan_from_spec` draft in PLAN Stage D.
2. **Make the long-horizon (goal→decompose→mechanical-advance) loop the
   default agent flow** (currently `PlanFrontierPolicy` is opt-in), bounded by
   running `run`/`verify` (Stage A) as the mechanical step that advances an
   `observable`/`open` step.
3. **A2a is the default arrangement**: a project build is a team of actors
   (planner/coder/verifier) sharing one `World`, each with its own flow/tools
   (via `FlowSpec` ADR-0014), projecting the same repo through the facet index,
   baton-on through shared threads + goals.
4. **`ask_user` = human-as-actor**: a `GenerationHandler` for a human; the
   model-facing actor can emit `ask_user` to pause and raise typed question/
   option — the "no external dream except when the LLM asks" goal.

## Non-goals / boundaries
- No AE import into the harness core (ADR 0015). The bridge stays a
  wire/schema consumer (`ae_bridge.dart`).
- No plan-schema-versioning engine, no re-planning policy engine (ADR-0009
  tripwires hold).
- `/refinement` tools are host features, not engine features (ADR 0015).

## Landed (2026-08-27)

- `planFromMatrix` in `tooling/build_gates.dart` — matrix rows -> Goal + Step
  beats (the AE-ETL harness seam), LLM-free-tested.
- `askUserTool` + `HumanAnswerProvider` — human-as-actor (a2h).
- `defaultGoalFlow` + `RunGradedGoalPolicy` — a Goal advances by running code.

## Consequences
- Coding agent closes the pi-parity gaps by composition (run + plan + a2h + a2a),
  not by a bigger model or a bigger cut.
- The tiny projection cut stays the token advantage (128k vs pi 1.29M); AE feeds
  a structured plan, and run-verifiers feed back compiled/ran evidence, both into
  facets — so the cut shows "what's built / does it run / last error / current
  step deps".
- The plan path "one sentence → AE matrix → goals/steps → build+run → verify"
  is the same thread that scales to a real repo or a real product.