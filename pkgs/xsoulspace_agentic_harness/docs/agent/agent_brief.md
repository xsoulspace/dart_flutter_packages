# Agent Brief — Agentic Harness: coding-agent first application + last_answer embedding

You are an autonomous coding agent. Work through this brief top to bottom.
Read the listed docs BEFORE changing anything — the architecture is deliberate;
most apparent shortcuts are forbidden for reasons recorded in ADRs.

## Repos & surfaces

- Monorepo: `~/xs/storage_problem/dart_flutter_packages`
  - Harness core: `pkgs/xsoulspace_agentic_harness`
  - AFM/CLI host: `pkgs/xsoulspace_inference_apple_foundation`
    (`bin/coding_agent.dart`, `bin/harnessd.dart`)
- ACP toolkit: `~/mcp/cline/intentcall/packages/acp_toolkit`
- Agentic Executables (AE): `~/xs/agentic_executables` (wire: `agentic_executables_wire`)
- Embedding target: `~/xs/storage_problem/last_answer`

## Read order (non-negotiable)

1. `pkgs/xsoulspace_agentic_harness/docs/agent/PLAN.md` — current race + rules
2. `docs/agent/architecture.mdx` — the loop + INVARIANTS (violating one is a bug)
3. `docs/agent/pipeline_coding.md`, `docs/agent/history.md`
4. ADRs: `0018` (zoom/context), `0019` (code law / tiers), `0020` (cut
   composition), `0021` (problems = AE-ETL canonical rows, project-guided repair
   packs) — in `docs/decisions/`
5. Evidence: `pkgs/xsoulspace_agentic_harness/benchmark/runs/delegation_m1_evidence.md`

## Entry points (already working — verify, don't rebuild)

- CLI: `dart run bin/coding_agent.dart "<task sentence>" --jail <dir>
  --backend apple_foundation_afm|open_router --check "<argv>" [--profile large]
  [--json] [--auto-approve] [--diff-gate] [--session/--resume <store>]`
- Daemon (ACP v1 over stdio): `dart run bin/harnessd.dart --backend open_router`
  — initialize → session/new(cwd) → session/prompt → streamed updates →
  permission round-trips (write gate) → verdict. Escalation: budget exhaustion
  returns a guidance request; the next prompt CONTINUES the same task.
- Self-improvement loop (ADR 0021): `dart analyze --format=machine` →
  `problem_board.dart` canonical rows → project repair pack
  (`repair_pack.json`, PROJECT-GUIDED — never core tables) → mechanical tier
  (zero model tokens, analyzer re-run oracle, auto-revert) → meaningful tier
  (one span-zoom decision, resolution CAPTURED back into the pack).

## Invariants you must not break

- The model NEVER writes code tokens in the meaning profile; the direct
  profile uses native fs tools (ADR 0019). Native tool calls for AFM and
  OpenRouter ONLY; other modes exist solely for untrained models.
- The cut is a composed document (ADR 0020): the codec renders slots verbatim,
  never re-ranks; required slots are an INPUT GATE (violations never dispatch).
- Repair executables are project-guided pack data. The model never chooses or
  supplies them (propose-as-data only via `declare_check`; host validates).
- Every harness test ends `expectIdle(world)`. Monotonic budgets — never reset
  counters. New Components append at the END of `AgentPlugin.install`.
- Every published number states backend, decision path, tokens source,
  composition, and n. Failures are data — classify, never drop.
- House rule: the coding agent fixes its own issues (delegated to its actors).
  You (the outer agent) orchestrate and escalate; do NOT absorb fixes the
  harness can do. OpenRouter (deepseek/deepseek-v4-flash-0731) is allowed but
  SECONDARY — AFM is the local-first goal (lean profile exists for its ~4k
  window: `--check` small scopes; pre-flight guard bounces over-window calls
  with `context_window_exceeded`).

## TASK A — make the coding agent first-application complete (AFM-first)

Goal: the user (or any agent) works with the harness exactly like they work
with pi today — task sentence in, mechanically verified work out, locally.

1. Drive one full loop per backend (AFM first, then OpenRouter) on a real
   small task; record rows (backend, decisions, tokens, failure class).
2. Run the self-improvement loop live: build the board over the harness's own
   packages, ensure the project repair pack covers the recurring classes
   (`dart/unused_import`, stale show-lists, unused locals), fix known classes
   mechanically (zero tokens), delegate only novel classes, capture their
   resolutions back into the pack. Publish rows in
   `benchmark/runs/delegation_m1_evidence.md`.
3. Close the UX gaps that stop a user from treating it as their coding agent:
   document the exact commands (README section in
   `pkgs/xsoulspace_inference_apple_foundation/`), session resume flow,
   escalation flow, and the repair-pack authoring format (one worked example).
4. Validation: `flutter test test/` green in both packages;
   `sh tool/check_bridge_swift.sh` 26/26; scripted suite pass; rows published.

## TASK B — embed the harness into last_answer (multiplayer surface)

Goal: last_answer hosts the harness as its first embedded domain host
(ADR 0015): the user creates/assigns tasks in the app; the daemon runs the
squad; the user watches progress and approves writes (permission round-trip).

1. Add the harness dependency to `last_answer` (path dep) and a host module
   that owns the daemon lifecycle in-process: start/stop `HarnessAcpBackend`
   (or `AcpStdioServer` over an in-memory channel), per-session worlds,
   snapshot persistence.
2. Minimal UI surface (coding agent FIRST, nothing else): task input (sentence
   + workspace), session list, streamed progress (tool updates + verdict),
   permission prompts (allow/reject per write), repair-pack editor deferred.
3. Multiplayer-ready: the app's user is an actor in the world — their task
   inputs are host-injected decisions; approvals ride the existing permission
   round-trip. Do NOT invent a second protocol.
4. Validation: a widget/integration test that starts a session with the
   scripted backend, delegates a task, answers one permission request, and
   asserts the verdict surfaces. LLM-free first; AFM optional behind a flag.
5. Constraints: no Firebase/account work; isolate the feature so the app
   builds and existing tests stay green (`flutter analyze`, `flutter test`).

## Definition of done

- TASK A: a user can run one command locally (AFM) and get mechanically
  verified work; the self-improvement loop has fixed ≥3 real issues at zero
  model tokens for known classes; rows + docs committed.
- TASK B: last_answer builds with the embedded harness; one scripted
  end-to-end session (delegate → permission → verdict) green; the daemon
  lifecycle controllable from the app.
- Both: all tests green (harness 322+, apple_foundation 16+, AE wire 10+),
  PLAN.md race-tracks updated, failures classified.
