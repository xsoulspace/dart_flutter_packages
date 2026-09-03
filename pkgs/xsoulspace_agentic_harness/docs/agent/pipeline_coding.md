# The coding pipeline — how coding actually happens

> THE doc for agents landing cold: one page, end-to-end, current state.
> Architecture-generic loop: [architecture.mdx](architecture.mdx) · durable
> decisions: ADR [0009](../../../../docs/decisions/0009_goals_as_vectors_plans_as_projections.md),
> [0015](../../../../docs/decisions/0015_domains_live_in_hosts_core_stays_generic.md),
> [0018](../../../../docs/decisions/0018_meaning_view_zoom_projection_context_ownership.md),
> [0020](../../../../docs/decisions/0020_cut_composition_api.md),
> [0022](../../../../docs/decisions/0022_workspace_oracle_meaning_pipeline.md)
> · forward plan: [PLAN.md](PLAN.md).

## The law (memorize this)

**Agent = G ∘ F.** The model is `G` — a tiny (2–4k) replaceable function from
a budgeted view to a few typed moves. `F` — decomposition, materialization,
verification, repair, projection, budgets — is ALL host code. The model
**never writes code tokens, never sees an AST, never holds the whole tree**.

> Scope (ADR 0019): this law is **absolute for code at every model size** —
> a 4k on-device model and a frontier hosted model compose the same meaning
> surface, because the law tracks verifiability, not artifact size: code has
> closed semantics (interpreter / oracle), so the model composes meaning and
> the host materializes. Untrained and invented languages strengthen the law
> (an invented language = an intent set + a materializer spec, both data,
> both host-verified). Free-form text (docs, prose, dialogue) is NOT code
> and was never under the law: it routes to the `evidence` tier, never
> `pass`. The surface grows intent-first (intents as data, host-verified;
> AE owns durable truth per ADR 0017/D2; IntentCall projects intents to
> MCP/ACP/platform), never vocabulary-by-hand.

## The pipeline (bookmark-manager reference path)

```
task sentence (host prompt, ~20 tokens)
   │
   ▼  model picks typed moves (1 decision per move; acks zoom to `point`)
act_with_project (ONE tool, closed sub-action enum):
    add/link/set_prop/list · macros: add_chain, link_chain (whole chains,
    host assigns ids)
intent_define: define / list — define is ONE self-executing action
    (B1 hard cut): it REQUIRES specs (op rows) and ALWAYS wires the
    `impl` edge + validates the chain host-side. Contract-only defines
    (no executor) are DELETED — that no-op path stranded J1.4 on-device.
    `redefine_chain` stays as an accepted alias for one release.
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
divergence bug was found and pinned this way). `intent_call` failures
carry ONE structured dialect (B2): intent name + defined intents + the
exact repair move ("re-send intent_define with specs").
   │
   ▼  REPAIR (bounded — J1.5 + B7)
Failure details carry op/intent ids → model fixes via set_prop /
define (specs). Verifiers (wireIntentGradedGoal / wireRunGradedGoal)
stamp GoalVerified mechanically; RunGradedGoalPolicy re-prompts at most
AgencyPolicy.maxGoalAttempts (3) times → then GoalAttemptsExhausted +
thread suspended (J8 rung 1). Driver-level repairs use openFreshDecision
(fresh round budget) and consume the SAME monotonic AttemptCount — never
an unbounded while(true). Every budget is monotonic: maxToolRounds
(12/chain), maxRetries (3, survives tool-call continuations),
maxGoalAttempts (3).
   │
   ▼  OBSERVABILITY — no more silent hangs (J1.5.3)
sampleHarness → HarnessPulse (per-actor decision stack, budgets, verdicts,
loop streaks, last tool result). FlightRecorder ring-buffers pulses,
detects identical-prompt re-open cycles, and dumps on maxTicks StateError /
SIGINT / driver exit — even on FAIL. Flutter UI: HarnessProfilerView
(shows the same zoomed cut the model sees).
   │
   ▼  RECOVERY — the overseer (J7/P2)
When the goal-attempt budget exhausts, the OVERSEER system spawns an
overseer actor whose decision sees ONLY the summary zoom + the structured
gate failure + the failing intent's chain dump (validateMeaningProgram +
an interpreter replay). Closed vocabulary via ONE tool: approve /
repair(intent, notes) / escalate(reason). repair re-opens exactly that
intent's scope (openFreshDecision on the MOVER, notes prepended; max 1
cycle — the attempt allowance widens monotonically, never resets). approve
NEVER forces a pass: the mechanical final oracle still decides. escalate
swaps to a higher Model.tier if the router declares one, else structured
FAIL.

## Host seams around the loop (P3/P5/P6)

- **Write gate (P3, revised)**: every jail file mutation — model `write`
  moves AND host materializer output — can flow through `JailWriteGateway`
  on `FsToolsRoot` (`apply` default / `review` renders unified diffs and
  asks the HOST approver). The model surface is unchanged; the law
  ("the model never writes code tokens") is enforced by P4's meaning-span
  edits, not by new model-facing parameters. Jailed read-only
  `git_status`/`git_diff` give bounded repo-state projections.
- **Persistent sessions (P5)**: `snapshotWorld`/`restoreWorld` drop
  transient state (stale verdicts, loop-smoke streaks, the escalation
  baton) and keep budgets (AttemptCount, ToolRoundCount), beats, open
  decisions, agency grants and in-flight awaits (crash-mid-decision
  recovery: the timeout sweeper turns a dangling await into a retry). A
  snapshot taken at idle restores idle-resumable.
  `coding_agent.dart --resume <store>` continues a saved session
  (`--session <store>` persists without resuming).
- **NDJSON transport (P6)**: `coding_agent.dart --json` streams one JSON
  object per line on stdout — this IS the editor-extension transport (D5:
  core learns no transport). Event schema:

```jsonc
{"type":"run_start","run":1,"task":"…","backend":"…","jail":"…","resumed":false}
{"type":"decision","run":1,"seq":1,"actor":"2","tool_calls":[{"name":"intent_define","args":{…}}],"responses_sent_delta":5}
{"type":"pulse","run":1,"text":"tick 4 | decisions 0 | …"}
{"type":"run_end","run":1,"verdict":"PASS","decisions":4,"tool_rounds":20,"tokens":7802,"moves":{…},"gate":[…],"failure_class":""}
{"type":"summary","row":"summary — task: … | n: 1 | pass@1: 1/1 | …","passed":1,"runs":1}
```

Human-readable lines move to stderr in `--json` mode. Decision-level
"tool_calls" come from the returned response (the AFM native path carries
every tool call there); the scripted suite handler sends its steps on the
event channel instead, so its decision events show `tool_calls: []` —
counts still match `responses_sent_delta`.
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
| On-device intent-closure driver (J1.4 benchmark) | `../xsoulspace_inference_apple_foundation/bin/intent_closure_afm.dart` |
| **On-device coding agent (THE deliverable)** | `../xsoulspace_inference_apple_foundation/bin/coding_agent.dart` + `lib/src/coding_agent_runner.dart` |
| Flutter profiler | `../xsoulspace_agentic_harness_flutter_profiler/` |

## Current situation (2026-09-01, post P1–P5)

- **Landed**: meaning tree as world state + zoom projection (ADR 0018);
  intent closure v1 (interpreter ⇄ materialized-Dart parity); macros
  (intent_03: 5 moves vs 24 micro-moves, suite 23/23 scripted); **B1** —
  `intent_define` collapsed to ONE self-executing action; **B2** — one
  structured failure dialect; **B4/B5** — legacy edit paths + crutch tests
  deleted; **B3/B7** — ONE on-device entry point `bin/coding_agent.dart`;
  **B8** — pass@3 protocol; **P1** — the AFM bridge generation-cancel
  contract (`xs_fm_cancel` + ABI version, no callback-after-delete crashes;
  the first post-B1 pass@3 set COMPLETED — zero bridge crashes, zero
  overflows); **P2** — the J7 overseer actor (summary-zoom brief, closed
  `approve/repair/escalate` vocabulary, scripted repair test green);
  **P3 (revised)** — the host write gate (`JailWriteGateway` on
  `FsToolsRoot`: apply/review modes, unified diffs, host approval — NO
  model-visible parameter) + jailed read-only `git_status`/`git_diff`;
  **P5** — idle-resumable snapshot restore + `--resume`/`--session` CLI;
  **P6** — `--json` NDJSON transport (host-side, D5). Full tables:
  [results_stage_p.md](results_stage_p.md).
- **Gate status (measured, results_stage_p.md §2)**: run-graded tier
  PASSES (bugfix_01 pass@3 = 3/3); intent tier honest FAIL 0/3 — the
  failure class is chain-logic correctness; the overseer grants ONE repair
  cycle (scripted proof green), on-device pass still open.
- **P4 (open, REFRAMED by ADR 0022)**: J3 analyzer round-trip in the host
  package `xsoulspace_agentic_dart_meaning` — `open(path)` + span-anchored
  edits. P4 closes the *editing* surface only (modifying existing files
  under the law). The run-graded arm's teaching prompt still says "make
  the change with write" — the model supplying whole-file content violates
  the never-writes-code-tokens law — but the *generation* path is NOT
  closed by span edits: the intent tier is closed in three independent
  ways (oracle replays host-authored expectations; 14-op vocabulary bans
  arithmetic/loops/intent-calls; materializer emits VM-replay, not
  workspace Dart). The generation law closes via ADR 0022's R6 tracks —
  workspace-oracle ETL (tests → canonical rows → intent skeletons), an
  idiomatic-Dart materializer spec, and vocabulary growth as verified
  data. Span edits become one projection of the Dart ETL. Until R6's
  ETL-in lands, the run-graded arm remains a transitional scaffold; no new
  model-visible write surface is added either way.
- **R6 STATUS (2026-09-02)**: the generation path is OPEN — ETL-in,
  the workspace-Dart materializer, and the vocabulary growth (21 ops incl.
  `call`) are LANDED and gated (`results_r6.md`: 1 decision, 7,857 tokens,
  `dart test exit=0`, zero model code tokens, zero host-authored
  expectations). Two of the three closures are now fixed: the oracle is
  the workspace (A-closure) and the materializer targets workspace Dart
  (C-closure). The vocabulary no longer bans arithmetic or intent-calls;
  loops remain bounded-by-recursion (V2 vocabulary), not free-form.
- **Next levers**: on-device AFM pass@3 through the workspace-oracle
  runner (the model now fills NAMED slots — strictly easier than the
  0/3 free-form authoring); tic-tac-toe-class task through the full
  runner; P4 span edits as the editing projection; J2 (context
  ownership), K-matrix rows beyond the two DoD tasks.

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
