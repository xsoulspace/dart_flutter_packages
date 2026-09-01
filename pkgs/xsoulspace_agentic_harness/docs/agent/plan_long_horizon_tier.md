# Plan — Long-horizon tier (Phase 8): the headline measurement

> Status: proposed. Binding context: ADR [0019](../../../../docs/decisions/0019_code_law_absolute_long_horizon_tier.md)
> (code law absolute at every model size; this tier is the headline), ADR 0018
> (context is harness-owned),
> [plan_fair_pi_comparison.md](plan_fair_pi_comparison.md)
> (conventional tier — its model-pinning and tool-parity rules carry over).
> North Star impact: `clarifies` — realigns the measured-claim program to the
> axis where the claim binds.

## Why this tier exists

The 20-task suite measures short, single-session, mainstream-stack coding —
the one axis where conversation-log agents with direct-edit grammars are
strongest and the harness's mechanisms are least load-bearing. The North
Star claim is about a *different* axis:

- sessions long enough that any context window fills or degrades (attention
  reliability degrades long before the window fills);
- **multiple sessions** per goal (persistence across snapshot/restore —
  memory is world state, not context);
- **multiple actors** sharing one world (a2a coordination that no per-agent
  log can represent);
- repo-scale beat graphs (hundreds to thousands of beats).

On that axis the hypothesis is structural, not aspirational: a
conversation-log agent ships its history every call (linear growth +
degraded retrieval); the harness projects a bounded cut every call (flat
tokens/decision, CI-gated since Phase 2). **No hosted-model, head-to-head
measurement of this axis has ever been run. This plan runs it.**

## Design

### Workloads

1. **Multi-session bugfix chain** — one goal spanning ≥5 sessions: run →
   snapshot → kill → restore → continue (the P5 mechanism at suite scale).
   Checker: deterministic (exit-0 / graded oracle) per session and for the
   chain.
2. **Cross-task repo tenure** — N≥10 sequential tasks against one growing
   world (the actor's beat graph accumulates across tasks; each new task
   must use prior-session knowledge via projection, not a fresh log).
   Checker: per-task graded oracle.
3. **Real-history replay suite** — tasks mined from this repo's own git
   history (bugfix commits replayed as tasks against the pre-fix tree,
   checker = the commit's tests). Infinite honest suite; also the
   dogfooding/self-improvement loop: the harness fixing harness issues,
   graded mechanically.
4. **Multi-actor shared workspace** — two actors, disjoint file ownership
   (per-file single-writer via the `JailWriteGateway`), one shared goal;
   graded on the composed result. Requires the single-writer rule landed
   first (design gap surfaced in the ADR 0019 discussion).

### Columns (every row stamped)

| Column | Why |
| --- | --- |
| backend + model id (pinned) + date | free-tier ids silently reroute |
| **domain** (code = meaning pipeline via intents; text = free-form, `evidence` tier) | ADR 0019 — code law is absolute at every model size; text was never under it |
| decision path (native; guided only if labeled exception) | ADR 0013 |
| tokens source (real usage vs projection) | C1 lesson |
| tokens/decision early vs late (flatness ratio) | the headline claim |
| tokens/decision **per session index** | persistence claim: flat across restarts |
| beats in graph at decision time | context-boundedness at scale |
| pass rate + failure class | failures are data |
| mechanical-step share | agency-discipline claim |
| wall clock | latency honesty |
| $/task + `cache_hit_rate` | **adoption metric only, never a claim** (ADR 0019 §6) |

### Harnesses compared (same model, same tasks, same checkers)

- **ours** — `coding_agent.dart --json` (native tool calling; OpenRouter
  messages codec), snapshot/restore between sessions.
- **pi SDK** — `createAgentSession()`, native loop, per-session prompt;
  multi-session simulated by sequential sessions with the session file
  persisting (its native persistence mechanism) — we measure *its* best
  persistence path, not a strawman.

### Gates (what "won" means, measured not asserted)

1. Flatness: our late/early tokens/decision ratio ≤ 1.2 across a ≥10× beat
   growth and ≥5 session restarts; pi's grows ≝ its log length (report the
   measured ratio).
2. Persistence: zero state-carry bugs across restores (restored actor
   idle-resumable, budgets persist, verdicts do not — P5 invariants at scale).
3. Pass rate: harness pass@3 ≥ pi pass@3 − ε on the long-horizon suite
   (being cheaper per token is worthless if it doesn't finish).
4. Tokens/task: harness total ≤ pi total × 0.8 on the long-horizon suite
   (the direction of the existing flatness evidence; the number is the
   deliverable, the threshold is the working hypothesis).

## Sequencing

1. Single-writer rule for shared fs (prerequisite for workload 4 only; 1–3
   are unblocked).
2. Real-history replay miner (git → task YAML + checkers) — LLM-free.
3. Extend the existing Dart runner for session chains (snapshot/restore
   between tasks — P5 mechanism, suite wiring only).
4. pi driver reuse from the conventional-tier plan (same tool).
5. Run workloads 1–3; add 4 after the single-writer rule.
6. Publish `results_long_horizon.md` with all columns; CI keeps the
   scripted LLM-free flatness-across-sessions gate
   (`test/long_horizon_multi_session_test.dart`).

## Non-goals / guardrails

- No core changes: workload wiring lives in the runner/benchmark layer;
  checkers stay single-sourced in Dart.
- No guided-schema rows except as labeled exceptions (ADR 0013).
- No caching tricks before the baseline exists — record `cache_hit_rate`,
  don't optimize for it yet (plan_fair_pi_comparison rule carries over).
- Conventional-tier losses are published beside this tier, unlaundered.
