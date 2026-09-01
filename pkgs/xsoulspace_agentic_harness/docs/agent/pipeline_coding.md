# The coding pipeline — how coding actually happens

> THE doc for agents landing cold: one page, end-to-end, current state.
> Architecture-generic loop: [architecture.mdx](architecture.mdx) · durable
> decisions: ADR [0009](../../../../docs/decisions/0009_goals_as_vectors_plans_as_projections.md),
> [0015](../../../../docs/decisions/0015_domains_live_in_hosts_core_stays_generic.md),
> [0018](../../../../docs/decisions/0018_meaning_view_zoom_projection_context_ownership.md)
> · forward plan: [PLAN.md](PLAN.md).

## The law (memorize this)

**Agent = G ∘ F.** The model is `G` — a tiny (2–4k) replaceable function from
a budgeted view to a few typed moves. `F` — decomposition, materialization,
verification, repair, projection, budgets — is ALL host code. The model
**never writes code tokens, never sees an AST, never holds the whole tree**.

## The pipeline (bookmark-manager reference path)

```
task sentence (host prompt, ~20 tokens)
   │
   ▼  model picks typed moves (1 decision per move; acks zoom to `point`)
act_with_project (ONE tool, closed sub-action enum):
    add/link/set_prop/list · macros: add_chain, link_chain (whole chains,
    host assigns ids)
intent_define: define / list / redefine_chain — redefine_chain is the
    repair macro: ATOMIC drop+rebuild of one intent's whole op chain.
intent_call: run an intent of the program you are building (in-process).
   │
   ▼  MEANING TREE = ECS world state (MeaningNode/MeaningProps/MeaningEdge)
intents are nodes (kind: 'intent') with `impl` edge → first op, `then`
chain → `return` op. Op vocabulary (closed): load_arg, load_state,
push_state, literal, list_len, starts_with, eq, not, jump_if_false, return.
Spec rows: label + props a/b; jump targets '#row'.
   │
   ▼  MATERIALIZATION (host program, model never sees it)
act_with_project action=materialize → materializeMeaningProgram(world)
   → jail/program.dart: initialState() + runIntent(name, state, args).
   Host-side validateMeaningProgram catches broken chains NOW (op ids in
   errors) instead of one oracle round later. Domains live in hosts (ADR
   0015): the core never knows Dart exists.
   │
   ▼  VERIFICATION — three tiers, all mechanical, no LLM
1. intent_call (in-process IntentRuntime interpreter over the tree)
2. intent-graded oracle: dart run intent_runner.dart replays
   intent_calls.json against the MATERIALIZED program (exit 0 iff all
   expectations hold) — strongest tier
3. runs checker: exit-0 of a target script
Parity: interpreter ⇄ materialized Dart is pinned by tests (a real AFM
divergence bug was found and pinned this way).
   │
   ▼  REPAIR (bounded — J1.5)
Failure details carry op/intent ids → model fixes via set_prop /
redefine_chain. Verifier loop (wireIntentGradedGoal / wireRunGradedGoal)
stamps GoalVerified mechanically; RunGradedGoalPolicy re-prompts at most
AgencyPolicy.maxGoalAttempts (3) times → then GoalAttemptsExhausted +
thread suspended (J8 rung 1). Driver-level retries use openFreshDecision
(fresh round budget). Every budget is monotonic: maxToolRounds (12/chain),
maxRetries (3, survives tool-call continuations), maxGoalAttempts (3).
   │
   ▼  OBSERVABILITY — no more silent hangs (J1.5.3)
sampleHarness → HarnessPulse (per-actor decision stack, budgets, verdicts,
loop streaks, last tool result). FlightRecorder ring-buffers pulses,
detects identical-prompt re-open cycles, and dumps on maxTicks StateError /
SIGINT / driver exit — even on FAIL. Flutter UI: HarnessProfilerView
(shows the same zoomed cut the model sees).
```

## What runs where (file map)

| Concern | File |
|---|---|
| The one tool + sub-actions | `lib/src/tooling/act_with_project.dart` |
| Meaning tree + zoom projection | `lib/src/meaning/meaning_tree.dart` |
| Intents + IntentRuntime + intent tools | `lib/src/meaning/intents.dart` |
| Materializer (op chains → program.dart) | `lib/src/meaning/meaning_program.dart` |
| Verifiers + goal loop + openFreshDecision | `lib/src/tooling/build_gates.dart` |
| Loop, budgets (canSleep), recorder sampling | `lib/src/harness_loop.dart` |
| Pulse + flight recorder | `lib/src/observation/harness_inspector.dart` |
| On-device driver | `xsoulspace_inference_apple_foundation/bin/intent_closure_afm.dart` |
| Flutter profiler | `../xsoulspace_agentic_harness_flutter_profiler/` |

## Current situation (2026-08-28, honest)

- **Landed**: meaning tree as world state + zoom projection (ADR 0018);
  intent closure v1 (interpreter ⇄ materialized-Dart parity); macros
  (intent_03: 5 moves vs 24 micro-moves, suite 23/23 scripted); context
  overhead 1,487 ≤ 1,500 tokens; J1.5 loop bounds + flight recorder +
  profiler — every loop monotonic-budgeted, every stuck run ships a dump.
- **Open blocker (J1.4 gate)**: on-device pass@3 = 0/3. The 2–4k model
  reliably calls `redefine_chain`/`materialize` but does not connect
  `intent_call` failures ("intent not implemented") to wiring a meaning
  executor. Diagnosed, not hidden — the pulse shows it per-decision.
- **Next levers**: J7/J8 (overseer actor + escalation ladder get the
  structured failure instead of the mover retrying), J2 (context-ownership
  experiment — session-per-decision bridge already committed), J3+ (Dart
  round-trip for EXISTING repos, via analyzer — host package).

## Invariants an agent must not break

1. New Component classes: append at the END of `data_models/components.dart`
   AND at the very END of `AgentPlugin.install` — ecsly assigns ids in
   registration order; mid-chain inserts corrupt host registrations
   ("Column should exist after archetype creation").
2. Never let the handler execute tools; the toolExecutionSystem path is one
   truth for native and tag-parsed calls.
3. Every harness test ends `expectIdle(world)`.
4. Every published number states backend, decision path, tokens source, tool
   surface, and n. Failures are classified data (see results docs).
5. Memory is projection over beat-threads; the meaning view is a zoom
   projection (point/local/region/summary); move acks zoom to `point`.
