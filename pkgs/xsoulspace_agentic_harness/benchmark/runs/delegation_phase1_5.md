# Delegation Phase 1.5 — THE HUMAN GATE (2026-09-05)

last_answer, agent-doc surface, **no terminal, no env vars**: the bridge
dylib is bundled in the Runner build phase, the loader resolves it from
inside the `.app`, and a human (the operator, driving the REAL GUI through
the established `flutter-mcp-toolkit` console — semantic snapshots, taps,
form fills, Dart evaluation, and the app's own MCP/intent entries) ran the
full agent-doc loop on this codebase.

## Gates

| gate | flow | backend | verdict | spend | n |
|---|---|---|---|---|---|
| bundling (build) | `env -u XS_FM_BRIDGE_PATH flutter build macos --debug`; dylib copied into `last_answer.app/Contents/MacOS/` by `macos/Runner/bundle_afm_bridge.sh` (Runner build phase) | n/a | build green, dylib in bundle, signed | — | 1 |
| AFM e2e (real app, NO env vars) | `flutter test integration_test/coding_agent_afm_e2e_test.dart -d macos` with a CLEAN environment | `apple_foundation_afm` (lean) | **PASS** | 1 decision, 3 rounds, 1,360 tokens, 28.8 s | 1 |
| self-profile (real repo, NO bridge env var) | `LASTANSWER_REPO=$PWD LASTANSWER_SELF_PROFILE=1 flutter test integration_test/coding_agent_self_profile_test.dart -d macos` (gate flags only) | `apple_foundation_afm` | **PASS** | 1 decision, 4 rounds, 1,591 tokens, 43.3 s | 1 |
| **GUI human loop (fixture task on this repo)** | launch app → create agent doc → bind workspace → set check override → delegate → permission round-trips → escalation → verdict banner PASS → fixture oracle exit 0 → fixture restored | `apple_foundation_afm` | **PASS** (turn 2, after an honest FAIL on turn 1) | turn 2: 1 decision, 17 rounds, 2,360 tokens, 34.8 s; moves read×4 write×4 run×3 git_status×2 git_diff×2 list_dir×1 goal_verify×1 | 1 |

Tokens source: backend verdict chunks (projection spend). Decision path:
host-injected `session/prompt` + ACP permission round-trips; deny-by-default
held on every unanswered/wrong write. n=1 per row (single runs, on-device,
macOS 26.6.2).

## Findings (each fixed product-side or filed — none dropped)

1. **Unanswered permission = unbounded 5-minute stall loop** (harness-side,
   filed): a write whose permission is never answered times out after
   5:00 (`TimeoutException after 0:05:00`), the model retries into another
   5-minute wait; cancel did not end the turn. Deny-by-default held (the
   write never landed), but a stuck turn was unstoppable. PRODUCT FIX:
   `HarnessSessionController.cancelCurrent` now rejects the pending
   permission before cancelling — measured live: the pending card cleared,
   the in-flight write got `REJECTED … NOT applied`.
2. **Check override never reached the daemon** (three compounding causes,
   all measured):
   a. semantic `enter_text` (editable_state) does NOT fire controller
      listeners → field-level agent fill silently bypassed persistence.
      Widget tests pass because human-typed input goes through the
      controller. PRODUCT FIX: the check field listens to the controller
      (not `onChanged`); the agent path must use intents (Phase 3: add
      `agent.doc.bind`), never form fills.
   b. doc-payload edits while a session existed never refreshed the
      controller config. PRODUCT FIX: `_syncConfigBeforeTurn()` (backend +
      check re-derived from the doc payload before every turn, key carried
      through — device-local, never doc data).
   c. `_switchBackend` persisted the doc backend AFTER the async switch →
      a concurrent delegate could revert the switch (measured: a real AFM
      session started inside a widget test). PRODUCT FIX: doc payload
      first, then switch.
3. **Cancel is not turn-interrupting** (harness-side, filed): after the
   product cancel fix the pending permission cleared, but the turn kept
   deciding (budget-bounded, eventually ended). `session/cancel` should
   abort between rounds promptly.
4. **First write of a turn may execute without a surfaced permission**
   (harness-side, F3, root cause not yet attributed): attempt 1's fixture
   write landed with no permission card (the agent's own `git_status` saw
   it modified); later writes asked and rejects held. Intermittent — needs
   attribution in `HarnessAcpBackend`'s write/edit approver wiring.
5. **Small-model off-task wandering on this repo** (known class): build-hook
   churn (`File modified during build`) confused the model's in-loop `run`
   verification; it proposed writes to `docs/index.mdx`,
   `src/main/test.dart`, `test/github_device_flow_real_test.dart` — all
   REJECTED by host policy, none applied. The OUTER oracle held every time.
   Repair-hint candidate (harness): "the check may hit build-hook churn;
   trust the final gate".
6. **App crash on cancel during a live AFM tool call** (bridge-side, filed
   with stack): `xs_fm_bridge.GenerationState.postToolCall` →
   `_dispatch_lane_barrier_sync` — the known callback-after-delete class
   resurfacing when the turn is cancelled while a tool call is in flight
   (`.showcase/human_gate_app2.log`).
7. **Semantic refs shift after every re-render**: `tap_widget` honors
   `stale_snapshot`, but `enter_text` via editable_state accepted stale
   refs silently (attempt 2: the check text landed in the task field and
   was delegated as the TASK). Drivers must re-snapshot before every fill
   (the console does not enforce it yet — upstream note).

## What was NOT claimed

- The GUI loop on THIS repo needed two turns (turn 1 honest FAIL with
  escalation; turn 2 PASS after guidance). A one-turn GUI pass on a huge
  repo with a small model is NOT claimed — the workspace-convention oracle
  (`flutter test`) plus a minutes-long grade surface remains the honest
  reason a human needs the check override for repo-bound docs.
- Widget tests still do not run AFM; the OpenRouter GUI path is verified
  for the missing-key error surface only (no network calls made).

# Post-refactor re-validation (ADR 0025/0026, 2026-09-05)

The concurrent refactor moved the daemon + ACP host policy into
`xsoulspace_agentic_host` (`HarnessEmbed`, `HarnessBackendBinding`,
provider-thin apple_foundation). Re-run against it:

| gate | backend | verdict | spend | n |
|---|---|---|---|---|
| clean-env build + bundled dylib | n/a | green (hook refreshed, phase copied) | — | 1 |
| AFM e2e (real app, no env vars) | `apple_foundation_afm` | **PASS** | 1 decision, 3 rounds, 1,323 tokens, 44.4 s | 1 |
| self-profile (this repo, no bridge env var) | `apple_foundation_afm` | **PASS** | 1 decision, 3 rounds, 1,554 tokens, 41.5 s | 1 |

New findings from the re-validation (none dropped):

8. **The gate can be destroyed by its own actor.** During a failing
   self-profile run the wandering model wrote to
   `integration_test/coding_agent_self_profile_test.dart` — and the test's
   blanket auto-allow user-actor LET IT THROUGH (the file was found
   truncated to one comment line afterwards). Fix: the scripted
   user-actor now allows ONLY fixture-path writes and rejects everything
   else (deny-by-default applies to the test harness too). The full
   permission log as UI data (this phase) made the incident traceable.
9. **`dart run` as the fixture check keeps derailing the small model**
   (build-hook churn, finding #4 confirmed twice more). The gate now uses
   plain `dart tool/agent_fixture/main.dart` — same oracle, no hook
   churn. Recommendation stands for fixture-shaped checks generally.
10. Runtime labels: AFM is the real-work default; OpenRouter (deepseek/
    deepseek-v4-flash-0731) is labeled the BACKUP in the surface.
