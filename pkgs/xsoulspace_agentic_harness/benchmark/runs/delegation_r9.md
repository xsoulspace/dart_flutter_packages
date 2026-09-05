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

## Findings (each named, none dropped)

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
