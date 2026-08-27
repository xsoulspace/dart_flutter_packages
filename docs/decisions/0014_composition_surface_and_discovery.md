# ADR 0014 — Declarative composition surface over the five seams; discovery tooling

- Status: Accepted
- Date: 2026-08-27
- North Star impact: `clarifies` — a general agent (coding **and** long-form
  writing **and** long conversation) stays a thin data-driven composition over
  ADR 0007's five seams, not a new framework.
- Builds on: [0005](0005_decision_flow_api.md),
  [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0013](0013_native_tool_calling_first.md)
- Related: `pkgs/xsoulspace_agentic_harness/docs/agent/composition_surface.md`

## Context

The harness thesis is "small model + heavy harness". Native tool calling is
now the default (ADR 0013) and guides the phase-4 comparison. But two limits
remain before the harness becomes a *general* agent:

1. **Discovery is the tool bottleneck, not the edit.** The jailed surface is
   only `read` / `write` / `list_dir` (+ `patch_file` / rename `patchSymbol`).
   There is **no search** (grep/glob) or structural locate. On a 2–4k model the
   budget dies on *finding* things, not on acting: a single `edit_01` cost 17
   recursive `list_dir`+`read` calls. Adding search is a mechanical win on
   every decision path and does not touch projection.
2. **The composition surface is design-only.** `composition_surface.md`
   proposes `FlowSpec` / `DatasetSpec` but none exist in code. A general agent
   that also writes long articles / screenplays / books and holds long
   conversations is a *set of different loops*, not different models — and
   loops/tools/schemas/evals should be declared as data, once, and run many
   ways (scripted / native / guided / pi-proxy).

The counter-force is ADR 0007's standing rule: **no sixth seam without three
logged failures, and no framework-breadth (North Star non-goal).** So the
question this ADR answers isn't "should we add generality?" — it answers *how
generality is delivered without opening the core*.

## Decision

### 1. Generality is exported as **data**, never as new core surface

A general agent is a composition of the **existing five seams** (ADR 0007)
described as declarative shapes:

- **Loop as data** — a `FlowSpec` (name + ordered `StageSpec[]` +
  `allowedTools` tool-surface gate + archetype) that a renderer turns into the
  existing `DecisionFlow` (ADR 0005) for model stages, plus mechanical stages
  (no LLM) for the rest, bounded by ADR 0009 goal/step projection.
- **Tools as data** — a `ToolSurface` on a `FlowSpec` gates which registered
  seam-3 tools the flow may wire. The registry — not the core — resolves
  actual tool bodies.
- **Eval as data** — a `DatasetSpec` (id + task/file refs + backend matrix +
  columns + **eval tier**) runnable against any backend through the shared
  matrix; tokens / calls / wall-clock / escalation per row already exist.
- **Schemas as data** — structure-as-beats (sections / scenes / dialogue
  turns) is a projection shape, not a new primitive.

**Hard rule:** the declarative shape-set is **closed** (a fixed set of stage
kinds and keys). Any task that needs real control flow beyond the closed set is
*a missing seam* — it must log three failed attempts through the existing seams
before a new stage kind or seam is even discussed (ADR 0007 §1). This keeps
"generality" from collapsing into an orchestration language.

### 2. Discovery is a ray-cast, not a recursive walk

Add `grep` / `glob` as jailed seam-3 tools so small models can *find* cheaply.
The structural `locate` tool (an elements/uses walk over a code index built on
disk) is the higher-order move and runs **token-bounded** like projection — a
ray over an index, not a brute list. ISBN of these tools: deterministic,
read-only, schema'd, never a projection replacement.

### 3. Eval tiers separate "passable" from "evidence".

- **Passable** (coding): deterministic checkers — pass/fail is a loud
  column (ADR 0009 verify).
- **Evidence** (long-form prose / dialogue): no falsifiable oracle — rows
  report *structured evidence* (structure beats, lint/consistency mechanical
  checks, oracle score) and are **never labeled `pass`**. This is the honest
  split the plan already demands ("failures remain data"; post-modern success
  only).
Fold both under one `DatasetSpec.evalTier`.

### 4. AE/matrix bounds the world, not the memory /.
`agentic_executables` (AE) output is *world-affordance* (domain structure,
schemas, spec↔code gaps) — an import for structured `See`-seam tools
(`verify_pack` already) and task fixtures. It is **never** the actor's memory
truth: beats + projection remain the sole runtime truth (North Star note 5).
The `composition_surface` integration stays a seam-3/4 composition.

## Non-goals / tripwires

- No plan-replanning engine, no planner agent, no plan-schema versioning
  (A2 tripwires hold).
- No framework-API breadth; the composition surface is a *declarative seam
  over the existing world*, not a new execution engine.
- No persistence of derived state as truth-source (facet index stays derived).
- No embedding of foreign agent runtimes.
- Prose quality is *drafted well by the harness, not authored at a bigger
  model's ceiling* — escalation is a legitimate, sharp exemption for **content**
  (writing), not for **coding** (where escalation should stay a fallback).

## Consequences
- General agent = data-driven composition; the core stays reviewable and
  statistically LLM-free testable.
- Discovery tools make the small model viable on big real codebases, closing
  part of the "own-codebase > SWE-bench" purity gap.
- `DatasetSpec` unifies coding + prose + dialogue evals with an honest tier
  column.