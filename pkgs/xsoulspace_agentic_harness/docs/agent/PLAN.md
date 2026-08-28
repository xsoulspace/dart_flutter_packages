# Agent Harness — Plan

> Forward/frontier record only. Landed work lives in
> [history.md](history.md); durable decisions in the
> [ADR Index](../../../../docs/decisions/README.md); benchmark numbers in
> `results_*.md`. Goal: a tiny-context (2–4k) cinematic multi-actor harness
> whose embedded coding agent codes **as well as pi** — e.g. "build a whole
> tic-tac-toe from scratch" — with a2a-native actors and AE-ETL for
> raw→structured→planning.
>
> This plan is written so **another agent can build and wire every piece**
> reliably. Each stage is independently testable, LLM-free, and ends with an
> `expectIdle`-clean harness test. Failures are data; gravity holds (tiny
> model stays useful; fewer LLM calls; context bounded+derived; LLM-free
> testable).

**Status (2026-08-27):** native tool calling default (ADR 0013); P2 discovery +
tool measurement + rename simplification landed (ADR 0016); composition
shape-set + host-boundary landed (ADR 0014/0015). **Gates A (run tool + runs
checker), B (run-graded goal loop default), C (a2h ask_user), and Stage D
(planFromMatrix) + C (a2a spawnActorBranch) are DONE**: each LLM-free-tested in
`test/run_tool_test.dart` + `test/build_gates_test.dart`, benchmarked scripted at flat
cumulative tokens vs baseline (2503/baseline vs 2503/run-graded). The 20-task
deterministic suite passes 100% scripted.

**Real-AFM re-measure (2026-08-27)**: `gate_run_afm.dart` on-device
(`AppleFoundationNativeClient`) — gates A/B make the loop **execute and observe**
its own output (run-graded board self-corrects across writes+runs after reading
the compile error; baseline flails in discovery). Both six-tool arms FAIL the
build tasks: a real 2–4k cut model cannot emit syntactically valid Dart.

**➜ resolution — one `act_with_project` tool (2026-08-27)**: same model, same
task, switch the surface to ONE tool with a closed enum (`add/list/link/
set_prop/materialize`) and hide the AST inside a host materializer: the model now
**only picks tiny moves** (add board/player1/player2 x3, link x3, materialize x1 —
no code token, no AST) and the host produces a **`dart run main.dart` exit=0**
game. `pkgs/xsoulspace_inference_apple_foundation/docs/results_act_with_project_afm.md`.
This is the load-bearing proof that the residual gap was surface-shape, not model-
capability — the model reasons in MEANING; structure/AST stay internal.*

---

## Target scenario (what "done" means)

An embedded coding agent, given **one sentence** — "build a tic-tac-toe game
in Dart, playable from the terminal, human vs computer" — with **no external
steering**, produces a compile-and-run `main.dart` that actually plays, and
**pauses only to ask the user questions/options** at model-chosen moments.
Metrics: ≥pi-parity pass on the interactive-build task; tokens/decision stay
flat; the loop is a2a-native (several actors can collaborate, swap models at
runtime, share Agency).

## The three gates (critical analysis, evidence-backed; PLAN 2026-08)

**Gate A — no `run`/execute tool.** The coding tool surface is
read/write/list_dir/grep/glob/locate/patch/rename/verify — *none execute*.
`Process.run` in tooling exists only in `ae_bridge.dart` (`verify_pack`).
A coding agent that cannot run `dart run main.dart`, compile, or run a test
**cannot observe whether its own output works**. pi's `bash` closes this.
→ **Build a jailed `run`/execute seam-3 tool + behavior-`verify`** (Stage A).

**Gate B — the loop is a bounded ReAct chain (maxToolRounds=16), not a
persistent plan/goal loop.** A whole-game build is dozens of tool calls; the
actor is dropped mid-build at the cap. ADR 0009 (Goal = verifiable vector;
Step on mechanical|observable|open) is implemented but opt-in
(`PlanFrontierPolicy` in `experiment_arms.dart`). → **Make Goal→decompose→
mechanical-advance the default flow**, wired through Gate A (a `run` advances
an `observable`/`open` step and writes evidence back as a facet).

**Gate C — no human-as-actor (a2h) affordance for "ask the user."** The presence
of the actor model says a human is just another handler, and `AwaitingResponse`
can wait on an LLM+tool+human simultaneously — but only the CLI's gated-tool
y/N approval is wired. → **Wire a `HumanActor` (a GenerationHandler) + an
`ask_user` decision/tool so a model-facing actor can pause and raise typed
questions/options to the user.**

**Corollary (design, not a gate):** the 4k projection cut is the *10x* token
advantage (128k vs pi's 1.29M) and must not be abandoned. The win is
**projection improvement + tools**: Gate A's run-results land as facets so the
cut includes "what I built / does it compile / last error"; Gate B's
decomposition keeps only the current step + its immediate deps in the cut so
small slices stay coherent. Cross-file coherence improves without sending more.

---

## Stage A — run/execute + verify that runs a program (the #1 build path)

**Goal:** the coding agent can execute what it builds and grade real behavior.

- [DONE] `ToolDef runTool(FsToolsRoot root)` (seam-3, `lib/src/tools/fs_tools.dart`):

  - name `run`, args `{command: string[], cwd?: string, timeout_ms?: int}`.
  - Resolve `cwd` inside the jail (escape protection like `read`).
  - `Process.run` with a cap (e.g. default 30s, override up to 120s); capture
    `exitCode`, `stdout`, `stderr` into a structured result (trimmed, e.g.
    first 4000 chars each) so it feeds the token budget.
  - Never lets the loop dangle: honor `AgencyPolicy.taskTimeout`, return a
    structured `{'ok': false, 'code': 'timeout'|'spawn_error', ...}` on failure.
  - Deterministic + LLM-free testable: `test/run_tool_test.dart` asserts a
    `dart` script prints `exitCode 0` + stdout, a failing script exit>0, a
    missing cwd → jail error, and a timeout → `timeout`.  **(built, green)**
- `A2` — `verify` grades by running: a new `verify_run` tool/checker that runs a
  command and grades stdout/exit-code against a predicate. Reuses AE's tier
  philosophy: `passable` vs `evidence` (see `DatasetSpec.evalTier`). Mechanical,
  never touches an LLM — raises `mechanical-step share`.
- `A3` — **trace through Measure** (ADR 0016): run `bin/tool_eval_profile.dart`
  on a `run`+`verify` sequence to confirm cost/latency added is small vs the
  loop turnaround it unlocks.
- **Done check:** a `dart run main.dart` that prints a board cells actually runs
  in a jar, exits 0, and a failing version returns nonzero — all LLM-free.

## Stage B — make a long-horizon (plan-frontier) loop the default

**Goal:** a whole build persists as a `Goal`; the loop advances mechanically.

- [DONE] `defaultGoalFlow()` + `RunGradedGoalPolicy` in `tooling/build_gates.dart`
  — a Goal advances by *running* code (the `run` tool stamps [GoalVerified]);
  the run-graded continuation leads the default flow. `test/build_gates_test.dart`
  proves a passed run terminates (no decision) and a failed run continues.
- [DONE] the `run` tool + `runs` checker (behAVioral oracle, exit-code) is the
  mechanical advance; `benchmark/coding_suite/checkers.dart` grades by executing
  the built target, not just string-equality.
- `maxToolRounds` stays as a per-step guard, not a whole-build cap.

---

## Stage C (a2a-native: many actors plan+work together)

**Why in-scope:** the system is **a2a-native by design** (`discussion.md`: any
Actor can address any other, high parallelism, runtime-swappable LLM, a2a/a2h/a2h2a).
So "build the game" can be a **team**: a Planner actor (goal/dev by AE-ETL step 1) +
a Coder actor (edits files, runs Gate A) + optionally a Reviewer/Verifier actor.

- [DONE] `spawnActorBranch` in `tooling/build_gates.dart` — a second actor in
  the shared world with its own open decision (a2a primitive). Deterministic;
  `test/build_gates_test.dart` proves it spawns. Parallel-agency swarm is bound
  by `AgencyPolicy(maxConcurrent)` and is a later stage.
- `C1` — wire two actors with distinct responsibilities, each routing to its
  own model/backend (`byAgent/byModel`).
- `C2` — baton-pass handoff between actors (A2 uses an `AskUser` tool + a
  shared `Goal` + thread), so the leaky separation holds ("planner produces
  steps; coder fills them; verifier runs them"). Reuse the `FlowSpec`
  (`composition_surface.dart`) to declare each role's loop + tool surface.
- `C3` — a headless `team` test: Planner plans → Coder edits+`run` → Verifier
  confirms → all idle. `expectIdle` for every actor.

---

## Stage D — ETL from agentic_executables (AE): raw → matrix → planning

**Why:** "raw unstructured → planning" is exactly AE's `KnowSource` (raw) →
`extractors`/`spec_importers` → `CanonicalMatrix` (structured) → `verify_report`
(tier), and the harness already has `ae_bridge.dart` (`verify_pack`, tier-order
beats). We use AE as **world-affordance** (ADR 0015), never as actor-memory.

- [DONE] `planFromMatrix` in `tooling/build_gates.dart` — an AE-style matrix
  (feature rows) → Goal + Step beats; `test/build_gates_test.dart` proves it.
- `D1` — tap AE build blocks (upstream `~/xs/agentic_executables`, NOT this
  repo's core):
  - `KnowSource` (raw text / repo / URL / PDF) → `RepoExtractor`,
    `SpecImportParser`, `dart_heuristic_extractor` → `CanonicalMatrix`.
  - `ae canonical import-spec` (a spec → canonical), `ae canonical distill`
    (partial).
- `D2` — a harness-side `plan_from_spec` tool (seam-3, `tooling/`) that:
  1. imports a natural-language brief (e.g. "build tic-tac-toe in Dart")
     via AE's spec/importer into a `CanonicalMatrix` (features/columns),
  2. renders that matrix as **goal + step beats** into the World, so the
     `PlanFrontier` (Stage B) drives building from the AE-derived plan,
  3. on `verify`, runs AE tier (`invariant_violation` > `upstream_blocker`)
     and feeds the tier-ordered gaps back as the actor's next decision.
- `D3` — a **`PlanForTask` policy** that reads the goal/steps and opens only the
  current step as the decision prompt — the same "what chunk of the plan this
  decision should act on" as ADR 0009 §4- projection union. LLM-free test uses
  the scripted handler + a fake AE matrix fixture.
- `D4` — end-to-end seam: `brief_sentence → (AE import-spec / distill) →
  CanonicalMatrix → plan steps → code+run (Gate A) → verify tier → idle`.
  Deterministic with a scripted/deterministic AE fixture; real AE optional.

**Keep-out (ADR 0015):** AE structures the world’s affordances; the **beats +
projection remain the actor’s truth**. No compiling AE inside the harness core.

---

## Stage E — human-as-actor (a2h): the "ask the user" seam

**Goal:** the agent pauses and raises typed questions/options to the user.

- [DONE] `askUserTool` in `tooling/build_gates.dart` — the model-facing actor
  emits a question + optional option menu; an injectable `HumanAnswerProvider`
  replies; the actor resumes on the answer. Deterministic + LLM-free;
  `test/build_gates_test.dart` proves the injected answer returns as a tool result.
- [DONE] `stdinAskUser` — default CLI provider calling the real `stdin`.

- `E1` — a `HumanActor` = a `GenerationHandler` whose `generate` reads a human
  answer (injectable: stdin / a `Future<String?>` UI callback), so the world
  runs it exactly like an LLM (ADR- bottom note: a human is another handler).
- `E2` — an `ask_user` decision tool (seam-1 `/seam-3`): the model-facing actor
  emits it, opens a `DecisionDraft`/`ToolCall` with `{question, options}`; a
  human answer lands as a beat / facet — no silent rewrite (mirrors
  `AgentCli.requestToolConfirmation` but for open questions, not just y/N).
- `E3` — CLI/UI wiring: reuse `AgentCli` approval callback; add a
  `HumanAnswer` handler for injectable answers in tests. `train/human-in-the-
  loop` LLM-free.
- `E4` — a single interactive scenario: build → compile-error → ask "retry or
  show me?" → user answers → agent reacts with the source fix and runs again.

---

## Stage A–E acceptance (the target, testable/started)

1. `run` + `run_verify` are registered in the coding jail, deterministic,
   time-bounded, LLM-free (`test/run_tool_test.dart`).
2. A `main.dart` tic-tac-toe sketch runs in the jail (`dart run main.dart` →
   exit 0; flaws → exit ≠0) with NO external steering.
3. A **default** goal→step loop (B) drives editing + `run` + `verify` and has
   `PlanFrontier` accessible not just via a flag.
4. a2a: a Planner+Coder(+Verifier) team completes it via shared threads; each
   actor ends `expectIdle`.
5. AE→matrix → goal/steps drives the loop when provided a brief (`plan_from_spec`).
6. The `ask_user` seam surfaces typed questions/options; a human answer
   continues the build. Everything paths LLM-free with the scripted handler.

---

## Standing rules

- Every published number states backend, decision path, tokens source, tool
  surface. Failures are data.
- Escalation-rate metric ships beside every pass-rate table.
- Extensibility ledger: three host entries vs the same seam → design conv
  (ADR 0007). Native tool-calling default (ADR 0013); plan/scopes
  internally via `FlowSpec`+`DecisionFlow`.
- Gravity: tiny model stays useful; fewer LLM calls; context bounded+derived;
  LLM-free testable. `expectIdle` ends every harness test. No spec-versioning
  engine, no planner agent beyond an actor that decomposes, no AE embed in core.

## Cleanup / hard-cut ledger (CI-paced)

- [ ] Delete legacy manual-schedule tests that mask the idle-race class.
- [ ] Remove dead/bisection probe bins after folding lessons into
  checks/tests (`bin/probe_*.dart`, `benchmark/debug_*.dart`).
- [ ] Keep `benchmark/runs/` evidence; drop throwaway probes.
- [ ] When Stage A lands, wire the new `run`/`verify` tools into
  `defaultToolSurface` and the coding-suite default arms.