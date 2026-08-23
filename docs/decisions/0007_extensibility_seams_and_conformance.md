# ADR 0007: Extensibility seams, conformance suites, and adapter policy

- Status: Accepted
- Date: 2026-08-24
- North Star impact: `clarifies`
- Builds on: [0004](0004_intelligence_grade_harness_evaluation.md), [0005](0005_decision_flow_api.md)
- Related: [0001](0001_native_ffi_bridge_acp.md), Phase 4–6 in `pkgs/xsoulspace_inference_core/docs/agent/PLAN.md`

## Context

The harness is becoming a platform: tools, decision policies, skills, MCP
servers, workflows, and hosts (CLI/TUI/Flutter) all need to be added **without
changing the framework** — the modding model. Content grows; the core does not.
Two forces must be balanced:

- The North Star non-goal: *"Not LangChain parity... framework-API breadth is
  scope creep."* A universal plugin architecture is the highest-breadth feature
  there is; done naively it violates gravity.
- The evaluation formula `Agent = G ∘ F` requires every mod to preserve
  determinism, or all metrics downstream become meaningless.

ADR 0005 admitted that predicate misuse is "mitigated by convention + review."
If extensibility is the mission, convention is not enough: a mod that silently
breaks purity or budget invalidates `F : State → State`.

Additionally, two reframings are recorded so they survive:

1. **Summarization is not a feature of this harness.** Projection over beat
   threads is the memory mechanism. Text summarization may exist only as a
   *reduction transform* — a classification/structurification step that turns
   long text into beats with facets. It feeds the graph; it never replaces it.
2. **Serialization** for snapshot/restore (Phase 6) uses
   `ecsly_serializable` + `universal_storage`. The facet index is derived and
   MUST be rebuilt from restored beats, never persisted as source-of-truth.

## Decision

### 1. Five seams, no sixth without three failures

Everything buildable enters through exactly five extension points, each with an
existing anchor:

| # | Seam | Extension point | Anchor |
| --- | --- | --- | --- |
| 1 | Decide | `DecisionPolicy` / `DecisionFlow` combinators | ADR 0005 |
| 2 | Act | `GenerationHandler` + `ModelRouter.inferenceClientsBuilders` | existing |
| 3 | Touch world | `ToolDef` + `ToolExecutorResource` | existing |
| 4 | See | `TokenEstimator` / projection parameters | existing |
| 5 | Persist | snapshot codec (`ecsly_serializable` + `universal_storage`) | Phase 6 |

A proposal that does not fit any seam requires **three concrete failed attempts
through existing seams first**, logged in the extensibility ledger (§4), before
a new seam type is even discussed. This operationalizes the repo rule "if the
same friction loops twice, stop before making another packet."

How known content types map today (no new seams):

- **Workflow** = a `DecisionFlow` + scripted beats.
- **Skill** = packaged knowledge beats + tool registrations + a triggering
  flow. Because skills are data (not code), per-skill attribution falls out of
  ADR 0005's `DecisionOrigin`: a skill whose beats are never projected into any
  cut is measurably dead weight.
- **MCP server** = a plugin package populating `ToolRegistry` from server
  listings (seam 3).

### 2. Conformance suites per seam

Each seam gets a deterministic conformance suite, following the
`universal_storage_conformance` precedent:

- **Policy conformance**: same fixture state → identical draft (determinism);
  ctx mutation canary fails in debug mode; no I/O from `evaluate`.
- **Tool conformance**: timeout honored; error-shape contract on throw/hang;
  result serialization round-trips.
- **Handler conformance**: the fault-mode matrix enumerated by `ScriptedTurn`
  (empty/error/throw/hang) produces the contracted failure shapes.
- **Projection conformance**: post-projection token count ≤ declared budget,
  asserted at runtime in debug mode, not just in benchmarks.

Runtime enforcement ships in debug mode (asserts), so purity violations surface
at mod development time instead of corrupting evaluations silently.

### 3. Adapter policy: standards, not host-specific shims

- **Consume MCP**: yes — MCP client support lives in a plugin package and
  registers tools via seam 3. Zero core change is the acceptance criterion.
- **Expose as MCP/ACP server**: yes (continues ADR 0001) — makes the Phase 4
  comparison scientifically clean: pi driving the harness vs native harness on
  identical tasks/tools.
- **Reuse pi extensions**: no. They bind to pi's hosting lifecycle
  (tool interception, TUI, session events), which this harness replaces;
  reuse would require a JS runtime or lossy shims and is provider-count
  chasing (explicit non-goal). The valuable interop surface is MCP servers —
  the open standard both ecosystems share.

### 4. Extensibility ledger

The everyday CLI (Phase 4–6 host) logs every occasion it needs a change to
core. Each entry names the pain, the seam attempted, and the disposition.
This ledger is the empirical seam list: three entries against the same seam
trigger the design conversation; entries that resolve inside a seam close it.

### 5. Snapshot/restore requirements (binding for Phase 6)

- Beats/threads/components persisted via `ecsly_serializable`, stored through
  `universal_storage`; `FacetIndex` rebuilt on restore (derived by design).
- Crash mid-decision restores to a **re-opened decision** — never a stuck
  `AwaitingResponse`.
- Golden oracle: post-restore projections byte-match pre-snapshot projections
  (exact-cut capture from ADR 0004 makes this cheap).
- Reduction transforms (summarization-as-structurification) are deliberate
  transforms with provenance (`SummarizesBeats`) and are re-runnable from
  sources after restore if needed.

## Consequences

- Platform growth happens in content and plugin packages; the five-seam core
  stays reviewable and LLM-free testable.
- Mods are individually conformance-tested; determinism of `F` survives
  third-party content.
- MCP interop imports the external tool ecosystem without provider-count
  drift; exposing as MCP/ACP gives clean Phase 4 comparisons.
- The ledger converts everyday-CLI friction into evidence instead of scope
  creep.

## Non-goals

- No generic event-bus/middleware plugin API ("everything is a hook").
- No embedding of foreign agent runtimes (JS VMs for pi-extension compat).
- No persistence of derived state (facet index) as source-of-truth.
- Summarization/compaction as an automatic memory mechanism remains a
  non-goal (see North Star extra note 1).
