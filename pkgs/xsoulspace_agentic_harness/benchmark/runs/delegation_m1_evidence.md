# Delegation M1 — first a2a dogfooding evidence (2026-09-02)

Driver: pi (deepseek via pi coding agent) delegating over process spawn to
`coding_agent.dart --json --backend open_router --runs 1 --json`.

## Row 1 — delegated_calc

- task sentence: "Implement lib/calc.dart so the test suite passes: provide int add(int a, int b) returning the sum of a and b."
- jail: seeded Dart package (pubspec + failing test/calc_test.dart); check = workspace convention `dart test` (D8/M0 — NO hardcoded checker)
- backend: open_router:deepseek/deepseek-v4-flash-0731 (pinned)
- verdict: **PASS** — decisions 11, tool rounds 15, tokens 15,725 (honest projection spend), wall 30.1s
- moves: list_dir×6 glob×2 read×4 write×2 run×1
- gate: `dart test exit=0`
- files: `delegation_m1_01_openrouter.ndjson` (PASS), `delegation_m1_01_pre_fix_FAIL.ndjson` (pre-fix)

## Bugs found by the FIRST delegation (the dogfooding payoff)

1. **Actor model id not router-resolvable (fixed).** The runner spawned the
   actor with a random `ModelId.create()`; the handler falls back to
   `Model(id: request.modelId)` whose name has no client builder →
   `initRuntime` throws → the actor NEVER generates. Measured: 3 verification
   attempts, 0 decisions, FAIL in ~2s. Fix: `actorModelId` param bound to a
   router-registered id; runner also keeps the host router (escalation reads
   the world's router; an empty resource silently degraded it).
2. **Empty `ModelRouterResource` overwrite (fixed).** `runCodingAgentOnce`
   replaced the host router with an empty one — agency capacity + escalation
   resolution silently degraded.

Both are integration seams invisible without a real end-to-end delegation —
the M1 shape earned its keep before Shape 2 started.

# Stage N — live squad evidence (2026-09-02)

## N1 — analyzer task board
LLM-free: machine-format parse → file-disjoint tasks, criterion = `dart analyze <file>`.
Tests: `analyze_board_test.dart` (4/4, incl. real analyzer on a dirty fixture).

## N2 — multi-actor squad (single process)
- Per-file single-writer: `FileLockTable` + per-actor gateways; cross-owner
  writes rejected with a structured ack BEFORE the gate; test proves
  rejected content never lands + release restores writability.
- Per-actor run-graded verification: `RunGoalSpec.commandByRegistry` keyed by
  registry name; verdicts stamp ONLY the pending actor.
- **Race found + fixed**: the verifier's subprocess completed AFTER
  `runUntilIdle` could sleep (P5 flake + squad 'no verdict stamped').
  Fix: verification runs as a REGISTERED task — canSleep() now waits for it.
- Tests: `squad_driver_test.dart` (2/2): two actors, two disjoint tasks,
  one world, board drains, idle.

## N3/N4 — daemon + pi joins (LIVE a2a proof)
- `bin/harnessd.dart` + `HarnessAcpBackend` over `dart_acp_toolkit`:
  initialize → session/new(cwd) → session/prompt(free sentence) → streamed
  session/update (tool_call_update per move, agent_message_chunk) → verdict.
- D8 end-to-end: check = workspace convention (`dart test`), zero per-task
  checker code.
- Protocol: **PASS** (pi drove the daemon over raw stdio JSON-RPC).
- Task outcome: **FAIL (honest)** — deepseek-v4-flash ran an exploration
  loop (26 decisions, 50 rounds, list_dir/glob, never wrote lib/greet.dart;
  `dart test exit=1`). Failure class: exploration/no-write. Feeds N5:
  loop-breaker catch + task-prompt templating (where to look, write early).

# ADR 0020 — Cut Composition API validation (2026-09-02)

## Root cause of the N4 exploration loop (traced, not guessed)
Flat relevance-ranked cut rendered as a conversation: (F1) scrambled slot-less
order — system prompt mid-sequence, tool results out of order; (F2) duplicate
reads consuming beat slots; (F3) empty `asst:` fragments admitted; (F4) no
working-set guarantee — the goal and the read test file were evicted, so the
model re-learned its environment every decision (27 decisions, never wrote).

## Fix
`CutComposition` (ADR 0020): typed slots — goal (non-evictable, input-gated),
map (absence-annotated until the fs graph lands), observations (relevance
selection, chronological render, dedup, drop-empty), lastVerdict. Codec
renders slots verbatim; never re-ranks. Input gate: unfilled required slots
fail as named `CutViolation`s before any model call.

## Conformance
`cut_composition_test.dart` 7/7: slot order, dedup, drop-empty, capacity +
chronological render within slot, goal survival under eviction pressure,
input-gate violation, integration through the real projection→actorAct path.

## Live before/after (same task, same model deepseek-v4-flash, fresh workspace)
| | N4 (flat soup) | ADR 0020 (composed) |
|---|---|---|
| decisions | 27 | 8 |
| tool rounds | 50 | 13 |
| tokens | ~38k | 10,735 |
| verdict | FAIL (exploration loop) | **PASS** |
| goal in every cut | no | yes (goalFirst=true ×8) |

d5/d6: `write` (the fix), d7: `run` (self-verification), d8: done.

# Stage N5 completion (2026-09-02, same day)

- **N5b fs-as-graph v1**: `WorkspaceMapProvider` — bounded tree (skip-list,
  `+N more` explicit absence), test→subject links with honest `MISSING`
  annotation, cached per root stat. Feeds the non-evictable `map` slot.
- **N5c roles**: `AgentRole` + per-registry compositions
  (`compositionByRegistry`). `roles_test.dart`: two roles on ONE model class,
  per-role cuts (overseer capacity-1 vs coder capacity-8) and prompts — the
  model ≠ actor claim, tested.
- **N5d a2a columns**: per-actor `decisions` + `projectionTokens` on every
  squad row.
- **M2b seeder**: `tool/seed_delegation.sh` — parent-commit package subtree
  → disposable jail (validated on a real commit).
- **Live re-delegation with map**: PASS, 7 decisions / 11 rounds / 9.9k
  tokens / `dart test exit=0`.

Full sweep at close: 46 harness tests + 6 apple_foundation tests, all green.

# Cleanup pass + open-issue closure (2026-09-02, later)

## dart_acp_toolkit changes (IntentCall repo)
- `AcpPermissionRequesting`: backends implementing it receive a client-
  permission requester at server startup (backend→client
  `session/request_permission` round-trip).
- **Concurrency fix**: the input loop awaited `_handleMessage` inline — a
  permission RESPONSE or `session/cancel` arriving mid-prompt was unreadable
  (round-trip deadlocked; cancel was dead code). Responses now route
  out-of-band; dispatch is concurrent (`_handleMessageSafe`).
- Tests: `permission_roundtrip_test.dart` + all 14 existing tests green.

## Harness side
- `HarnessAcpBackend` implements the interface: the write gate runs in
  `review` mode — every write asks the client (pi/human approves diffs).
- **pi-as-escalation-rug (N4)**: budget exhaustion → structured escalation
  chunk → the next client prompt CONTINUES the same task through the
  repaired world with a widened monotonic allowance (`maxGoalAttempts`
  param); PASS clears it. Scripted LLM-free proof:
  `harnessd_escalation_test.dart` (turn1 FAIL+escalation → turn2 PASS).
- **M0b landed**: `declare_check` tool — the model PROPOSES its verification
  command as data; host validates (binary allowlist, metacharacter
  rejection); the verifier executes mechanically. Proposing is never
  self-grading. Tests: `declare_check_test.dart` 5/5. Wired behind
  `runCodingAgentOnce(allowDeclaredChecks: true)` (daemon on).

## AFM reliability — P1 closure criteria (the critical pass)
Three layers now guard the recorded crash (timeout + callback-after-delete
after 'Exceeded model context window size'):
1. ABI v2 cancel contract — Swift `GenerationState` queue-gated callbacks,
   Dart cancels BEFORE teardown (landed earlier).
2. NEW Dart pre-flight: `AppleFoundationNativeClient(maxContextTokens:
   3800)` — over-window requests fail NAMED (`context_window_exceeded`)
   before the bridge is called.
3. NEW Swift: context-window errors map to the same named code
   (belt-and-suspenders; needs a macOS bridge-test run).

**When can we reliably work with AFM?** When: (a) one green on-device pass@3
through `coding_agent.dart` completes post-fixes (the recorded crash killed
two mid-benchmark runs — this is the gate), and (b) the macOS bridge test
suite (`bridge/tests/BridgeTests.swift`) runs green with the Swift change.
Neither has run yet; both are runtime-gated on this machine, not blocked by
open code work.

# AFM runtime gates CLEARED (2026-09-02)

## Gate (b) — macOS bridge test suite
`sh tool/check_bridge_swift.sh` → **26 passed, 0 failed** — unit tests
(cancel contract, callback-after-delete guards, tool payload routing) AND
live AFM sessions A–H (plain, nil-schema, materialized schemas, multi-tool,
macro/reflected/raw-capture tools). Includes the Swift
`context_window_exceeded` mapping change.

## Gate (a) — on-device pass@3
`coding_agent.dart --task bugfix_01_off_by_one --runs 3` (apple_foundation_afm):
**pass@3 = 3/3**, tokens/run [1302, 1302, 1302], decisions/run [1,1,1],
context overflows: 0, zero native crashes. The tool loop (write → run →
done) worked; the model recovered from a path-escape bounce (structured
teaching error) unaided.

## Also
- Dead duplicated `accepted <= 0` block removed from
  `native_client.dart` (7/7 bridge tests + scripted run still green).

**Verdict: AFM is UNBLOCKED** — all three guard layers are runtime-verified;
the on-device actor can rejoin the squad (N5 tail).
