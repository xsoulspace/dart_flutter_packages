# Composition Surface — declarative agent construction

> Status: [**accepted**] — decision + guardrails live in
> [ADR 0014](../../../../docs/decisions/0014_composition_surface_and_discovery.md). This
> file is the frontier implementation detail of that stance: how loops,
> tools, schemas, and evals are declared as data over the five seams
> (ADR 0007), and how the tiny context stays bounded.
> Scope guard per AGENTS.md gravity: every feature must shrink tokens-per-task
> or keep context bounded. Generality is exported as **data**, never as new
> core surface (ADR 0007 §1 hard rule).

## Shipped increments

- **Discovery (Stage 1)** — jailed `grep` / `glob` seam-3 tools in
  `fs_tools.dart`; the concrete bottleneck cut (17-call edit discovery →
  cheap find). Wired into [ADR 0014](../../../../docs/decisions/0014_composition_surface_and_discovery.md) §2.
- **Structural `locate` ray-cast (Stage 1.5)** — `tooling/locate_index.dart`:
  a deterministic identifier index over the workspace; `locate` answers
  "where is X defined / used" in one token-bounded, jailed call. Code
  output-agnostic, JSON-serializable for AE-shaped world-affordance. See
  `test/locate_index_test.dart`.
- **Dialogue/prose composed end-to-end (host demo, ADR 0015)** — a
  `dialogue` archetype `FlowSpec` declared in YAML, rendered onto
  [DecisionFlow], gated to a surface, and driven through `HarnessLoop` by a
  scripted handler (`test/composition_dialogue_e2e_test.dart`). This is a
  **host::demo** showing how a domain (e.g. `last_answer`) composes the
  generic surface — NOT a core feature. The core interprets no `archetype`.
- **Declarative surface (Stage 2)** — `lib/src/composition/` with `FlowSpec`
  (closed `StageSpec[]` + `ToolSurface` gate + **free-form** `archetype`),
  `DatasetSpec` (tiered eval: `passable` vs `evidence`), and `renderFlow` mapping spec stages to the existing `DecisionFlow` builders
  (ADR 0005). LLM-free testable; no core-loop change.

## The gap this addresses

Native tool calling is now the default (ADR 0013). But a general agent needs
more than a default tool loop:

1. **Varied task shapes.** Coding (read → edit → verify), prose (plan →
   draft → revise → structure), long dialogue (stateful, bounded context,
   episodic). These are *different loops*, not different models.
2. **Evals / datasets as first-class.** Current SWE benches are trivial next
   to the repo's own codebase. Repeatedly rewriting per-task YAML is manual.
   We want "take examples / evals on them" — data declared once, run many
   ways (scripted, native, guided, pi-proxy).
3. **Keeping "external composition API" door open.** Logic, tools, schemas,
   loops defined *declaratively* (data/DSL), not hard-coded in host bins — so
   the same world drives many front-ends and the modding model (ADR 0007)
   stays true.

## Direction (falsifiable, phase-gated)

1. **Loop as data today.** The harness already has `DecisionFlow` (ADR 0005)
   and `TransformFlow` (M2). A next increment: express a *loop* as a
   declarative `FlowSpec` (stages + a tool-surface gate + a free-form
   `archetype` label) that a runner turns into a `DecisionFlow` for the
   model and mechanical stages (no LLM) for the rest — with the ADR 0009
   goal/step projection used to bound the cut.
2. **Eval suite as data.** A `DatasetSpec` referencing `tasks/**` YAML +
   checkers + expected columns, runnable against any backend
   (native/guided/pi) via a shared matrix driver; tokens/calls/wall-clock per
   row already exist (`CodingSuiteRunner`). The `EvalTier` split
   (`passable` vs `evidence`) keeps deterministic-checkable rows loud and
   evidence-only rows honest — regardless of the host domain.
3. **Content targets are HOST work, not engine work (ADR 0015).** Long-form
   (article/screenplay/book) and long conversations get the same generic
   projection/budget rails — but the *product* shape (sections, scenes,
   dialogue turns as beats, format/lint/consistency verifiers) lives in the
   host (e.g. `last_answer`). The harness supplies the generic shape and the
   embedding surface; it does not curate a domain model.

## Non-goals / scope-tripwires

- No framework-API breadth (North Star non-goal). Any new surface that isn't
  a *declarative seam* over the existing world/lips is scope creep.
- No plan-replanning engine, no planner agent, no plan-schema versioning
  (A2 tripwires hold).
- No MCP server as a prerequisite; composition is a data-shape first.

## Related "agentic-executable" effort (separate, sibling)

`~/xs/agentic-executable` is a separate project on transforming unstructured
raw text → (generatable) matrix ↔ code with ETL-style pipelines. This doc's
composition/eval direction is complementary, not overlapping: the harness's
Situation-purposed projections match the "matrix/generatable" intermediate
representation. A concrete integration would let a declared second agent
(classify/structurize) be composed with a coding agent on the same world —
discussed, not yet shipped.
