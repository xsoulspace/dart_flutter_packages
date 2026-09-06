# Delegation R9 — the console migration (2026-09-05)

last_answer becomes the operator console. R9.a landed: the missing verbs
(`agent_doc_create`, `agent_doc_bind`, `agent_task_guide`) are registered
MCP/intent entries (`lib/coding_agent/agent_mcp_tools.dart`, mcp_toolkit +
intentcall `AgentCallEntry`), and the FULL headless operator cycle ran
against the real macOS debug app with ZERO GUI clicks and ZERO field fills:

```
flutter-mcp-toolkit exec --name fmt_client_tool --toolName agent_doc_create
  → agent_doc_bind (workspace + check override, never a form fill)
  → agent_task_delegate → agent_permission_answer → agent_doc_state
  (verdict + spend read back through the same projection)
```

Gate script: last_answer `tool/r9a_gate.sh` (launches the debug app, parses
the VM service URI, drives the intents, restores the fixture on exit).

## Rows

| gate | flow | backend | verdict | spend | n |
|---|---|---|---|---|---|
| R9.a headless cycle (run 1) | create → bind → delegate → permission round-trips → verdict read | `apple_foundation_afm` | **FAIL** (turn 1, honest) — verdict read back through `agent_doc_state` | allowed 6 (fixture writes) · **REJECTED 10** (off-task `lib/main.dart` writes — deny-by-default held on every one) | 1 |
| R9.a headless cycle (run 2, final) | create → bind → delegate → permission allow → verdict PASS → fixture oracle exit 0 → fixture restored | `apple_foundation_afm` | **PASS** | 1 decision, 3 rounds, 1,552 tokens, wall 43.6 s; moves read×1 write×1 run×1 | 1 |
| widget gates (LLM-free, scripted mover) | `test/coding_agent/agent_intents_test.dart` — create returns docId (+ honest refusal when unwired), bind persists payload + refreshes daemon config + refuses relative paths, guide FAIL→GUIDE row→continuation PASS (+ no-session / mid-turn refusals) | scripted | **16/16 green** in `test/coding_agent` | — | 5 |

Tokens source: backend verdict chunk (surfaced verbatim in the transcript
tail: `verdict: PASS (decisions 1, rounds 3, tokens 1552, wall 43625 ms,
moves {read: 1, write: 1, run: 1})`). Decision path: host-injected
`session/prompt` (delegate + guide) over the ACP permission round-trip.
n=1 per row (single runs, on-device, macOS 26.6.2).

## Rows (R9.1 — the meaning runtime, 2026-09-06)

| gate | flow | backend | verdict | spend | n |
|---|---|---|---|---|---|
| R9.1 meaning e2e, run 1 (real app, no env vars) | fixture task through the meaning tree (repo_etl → zoom → impact → edit_symbol) | `apple_foundation_afm` | **FAIL** (discovery loop — finding 9) | 4 decisions, 19 rounds, 10,147 tokens, wall 199.4 s; moves scan×4 zoom×5 impact×5 edit×2 refresh×3 | 1 |
| R9.1 meaning e2e, run 2 (after the finding-9 fix) | same | `apple_foundation_afm` | **FAIL** (cut fatness + re-scan churn — findings 10/11, open) | 7 decisions, 5 rounds, 38,299 tokens, wall 46.1 s; moves scan×2 zoom×2 refresh×1 | 1 |
| A/B reference: conventional self-profile (recorded 2026-09-05) | same workspace, same oracle, command profile | `apple_foundation_afm` | **PASS** | 1 decision, 3 rounds, 1,554 tokens, 41.5 s | 1 |

Tokens source: backend verdict chunks. The honest reading: the meaning
surface's MACHINERY is right (ETL 812 files / 4,567 symbols in-app;
bounces carry repair hints; the overhead gate enforces the window) but
its tiny-model ERGONOMICS are not yet — the A/B is currently dominated by
the conventional profile on a trivial task. That is the measured frontier
"reach quality for AFM with the agentic harness" starts from; findings
10/11 are the harness's next work items, pulled, never absorbed.

## Findings (each named, none dropped)

9. **Meaning-profile discovery: the query ray-cast sent as `zoom=point`
   silently returned an EMPTY cut** (point admits focus ids only and
   ignores the query — the actor looped on nothing, run 1: 4 decisions,
   19 rounds, 10,147 tokens, 199 s, FAIL). FIXED in-session
   (`meaning_query_tools.dart`): a query-only point zoom degrades to
   `zoom=local` with a named note; every cut echoes its query/focusId;
   an empty ray-cast returns keyword-matched id hints (the same
   repair-hint pattern as the unknown-focusId bounce). Run 2 confirmed
   the ray-cast returns real candidate ids.
10. **Meaning-profile cuts are too fat for the 3.8k AFM window (OPEN —
    harness track).** Run 2: 7 decisions, 5 rounds, **38,299 tokens**
    (~7.6k tokens/decision observed vs the flat ~2k projection target),
    wall 46 s, FAIL — the model never reached an edit. The local-zoom
    fill + verbose node props blow the budget the overhead gate
    (1,600-token fixed surface) implies. Candidate levers: per-window
    `maxNodes`/props projection (lean node JSON), cut budget derived from
    the resolved model window (P1 maxContextTokens), not a constant.
11. **`repo_etl` re-scan churn (OPEN — agentic_workspace track).** A
    second `scan` returns `ok:false "tree already built — use action
    refresh"`, which the model treats as a failure signal and loops on
    (refresh ×3 in run 2). Candidate: return `ok:true` + a named
    `already_built` note (a no-op is not an error), or a bounce-with-
    repair shape the model follows. NOT absorbed: `repo_etl_tool.dart`
    is the concurrent session's file.
12. **The teaching prompt is budget-gated (positive finding).**
    `meaning_profile_overhead_test.dart` (fixed overhead ≤ 1,600 tokens
    against the 3,800-token AFM window) caught the first prompt rewrite
    (+86 tokens) and forced the recipe down to exactly 1,600 — the
    window law is enforced by a test, not by vibes.

6. **Conversation-profile blind writes corrupt targets (R9.b, THE
   trigger for the redefined plan — ADR 0004 in last_answer).** The
   dogfood run (fix ProjectView wiring through the conversation surface):
   the model made 4 allowed whole-file writes to `lib/home/
   project_view.dart` and the final state REPLACED the file with broken
   nonsense (a self-referential MaterialApp stub). The outer mechanical
   oracle held (check exit 1 → honest FAIL verdict) and nothing outside
   the target was touched — but the "right" file itself was corrupted.
   Class: in the conventional command profile, a small model's whole-file
   `write` is one diff away from destruction with nothing between decision
   and disk except a title-only consent prompt. In the meaning profile the
   shape is impossible-by-construction (edits are span moves the host
   materializes, verifies, auto-reverts; `write` does not exist).
   Resolution: R9.1 — the meaning runtime becomes the agent doc's only
   embedded profile.
7. **The in-loop `run` tool's 30 s default timeout cannot fit test-compiling
   gates** (R9.b prep): `runGoalVerifier` invokes the run tool without
   `timeout_ms`, so a doc check override of `flutter test <file>` fails on
   the compile alone. Harness-side fix candidate: pass a verifier-scoped
   timeout (or honor the task's declared grade budget). R9.6's mechanical
   check is a plain `dart <file>` script as a consequence.
8. **Driver ergonomics: `agent_doc_state` could not report the check
   override or the runtime profile** until R9.a added `checkCommand` /
   R9.1 added `runtimeProfile` — keep the projection dense enough to
   drive from (standing rule).

1. **Create → surface-open lag (product, R9.a)**: after
   `agent_doc_create`, the route push + first mount of the doc surface can
   lag tens of seconds on a cold debug build. Drivers MUST poll
   `agent_doc_state` until it reports the created docId — and
   `agent_doc_create` doubles as the app-readiness probe (the create hook
   installs with the home shell). Recorded in the gate script.
2. **The intent permission path enforces the same policy as the GUI**
   (positive): run 1's wandering model attempted TEN off-task writes to
   `lib/main.dart` through the intent-driven session — every one was
   REJECTED via `agent_permission_answer {'allow': false}` and none landed.
   Same named class as Phase-1.5 finding #5 (small-model off-task
   wandering); deny-by-default held; failures are data.
3. **The in-loop `run` tool cannot execute `dart tool/agent_fixture/
   main.dart` from the jail** ("Could not find a command named \"tool\"")
   while the OUTER oracle (the doc's check override) runs the same command
   fine. Repair-hint candidate for the harness: "the check runs from the
   workspace root; your in-loop run tool may resolve cwd differently —
   trust the final gate." (Phase-1.5 finding #5's sibling.)
4. **The scripted seam's `handlerFactory` is invoked PER TURN**
   (harness-side, for future gate authors): per-turn state (e.g. a single
   scripted write) must live on a SHARED mover instance, not on a fresh
   one created inside the factory — otherwise every turn restarts the
   script and a guided continuation re-writes.
5. **`agent_task_guide` semantics** (product, as landed): host-injected
   decision, monotonic per turn (one guidance per ended turn; a NEW turn
   may be guided again), recorded on the turn it responds to as a
   first-class GUIDE grid row + composer pre-fill — never a transcript-only
   line. The continuation sentence is `continue with guidance: …`.

## What was NOT claimed

- One-turn PASS on this repo is NOT claimed (run 1 was an honest FAIL;
  run 2 PASSed on a clean second launch). The escalation path
  (FAIL → guide → PASS) is widget-gated but not yet exercised live on this
  repo — that is R9.b/R9.d's row.
- OpenRouter path untested from the intents (AFM is the real-work default).
- The created agent docs persist in the app's storage (operator docs, not
  gate artifacts).
