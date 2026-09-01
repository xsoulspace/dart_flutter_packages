// ignore_for_file: lines_longer_than_80_chars

/// Stage J1.5 results — loop bounds + runtime observability.
/// LLM-free (scripted backends) unless marked on-device (AFM).

# Stage J1.5 results (2026-08-28)

Acceptance evidence for PLAN §J1.5. Sources: `tool/j15_benchmark.dart`
(A/C/D), `test/loop_bounds_inspector_test.dart`, the on-device AFM driver
`xsoulspace_inference_apple_foundation/bin/intent_closure_afm.dart`, and the
existing suite profile (`bin/harness_profile.dart --all`). Every number below
states its backend and measurement source.

## 1. Whole-system health (scripted, deterministic)

| Check | Result | Source |
|---|---|---|
| Harness test suite | **358 passed / 0 failed** (baseline was 349+0) | `flutter test`, baseline diff |
| Coding suite | **23/23 (100%)**, 40,567 tokens total, 2s wall | `bin/harness_profile.dart --all` |
| Golden headless examples | 4/4 green (incl. `03_scripted_faults` retry path) | `just demo` |
| Gate-B benchmark | baseline vs run-graded both pass at flat 5,001 tokens | `bin/build_gate_benchmark.dart` |
| Profiler view package | analyze clean, 3/3 widget tests | new package |
| Context overhead (J1.2) | **1,487 ≤ 1,500** of the 4,096 window | `intent_closure_budget_test.dart` |

## 2. Observability cost (benchmark A)

`sampleHarness` per-call, 1 actor + N tool beats (mean of 200 calls):

| World load | µs/pulse | share of the 1kHz tick budget |
|---|---|---|
| 8 beats | 21.3 | 2.1% |
| 64 beats | 16.5 | 1.7% |
| 512 beats | 13.2 | 1.3% |

`FlightRecorder.record`: **1.35 µs/pulse** (2,000-call mean). `dump()` on a
full 256-pulse ring: **~1.1 ms** (exit-time only). Verdict: the profiler tax
is noise — auto-sampling every 100 ticks costs ≈0.2% of wall time.

## 3. Loop-bound efficacy — incident replay (benchmark C)

Scripted model that thrashes on a permanently failing intent oracle
(`maxGoalAttempts: 3`):

| Metric | Pre-J1.5 (analytic) | Post-J1.5 (measured) |
|---|---|---|
| Termination | **unbounded** — prose turns reset `ToolRoundCount`; the only stop is the 2M-tick StateError (~35 min, zero data) | **136 ms**, bounded |
| Failed attempts before stop | ∞ | 3/3, then `goal_unverifiable: 3 failed verification attempts` |
| Terminal state | spin → throw | thread `suspended`, `GoalAttemptsExhausted` + structured reason, world idle (0 open decisions, 0 stranded) |
| Named the loop? | no ("check for retry loops…") | yes — pulse warning + flight-recorder dump |

## 4. J1 move density (benchmark D — scripted, same oracle)

| Task | Arm | Moves |
|---|---|---|
| intent_01 | write-arm (single big write) | 1 |
| intent_02 | meaning micro-moves | 24 |
| intent_03 | **macros (J1)** | **5** |

J1 target "≤ 6 moves/subtask": met by the macros arm.

## 5. On-device validation (AFM, Apple Foundation Model — honest FAIL + the monitor's catch)

Two full `bin/intent_closure_afm.dart` runs, same task, one attempt each
(n=2, not pass@3 — J1.4's gate is still OPEN):

| Column | Run 1 (pre-J1.5.6) | Run 2 (post-J1.5.6) |
|---|---|---|
| Decisions | 7 | **4** |
| Tool rounds | 51 | **19** |
| Moves | 51 (40 redefine_chain, 3 materialize, 7 intent_call, 1 list) | **19** (10 redefine_chain, 2 materialize, 6 intent_call, 1 define) |
| Projection tokens (honest spend) | 14,841 | **10,198** (−31%) |
| Oracle | FAIL (retries 3) | FAIL (retries 3) |
| Failure class | **unbounded `backend_failed` retry loop** (flight recorder: *"decision prompt repeated 255× (identical)"*) | **capability**: model defines intents but never wires a meaning executor ("no meaning executor for intent: save_url") — honest, bounded FAIL |
| Loop named by the monitor? | yes — prompt + actor + origin, post-mortem on exit | yes — final pulse shows the last failing `intent_call` with the structured error |

### Findings the monitor made during on-device testing

1. **J1.5.6 (fixed, regression-tested)**: `RetryCount` was reset by *every*
   resolved response — including mid-chain tool-call continuations. A flaky
   backend alternating `backend_failed → tool-calling response` retried
   forever (the observed 255× loop). Fix: the error-retry budget survives
   tool-call continuations and resets only on a text-only final answer
   (ADR 0004 chain semantics). Test: `loop_bounds_inspector_test.dart`
   → "flaky backend … exhausts the retry budget".
2. **Detector false positive (fixed)**: a decision held open during a ~60 s
   on-device generation, sampled every 100 ticks, looked like a 163× loop.
   The detector now counts **open→closed→open cycles**, not consecutive
   snapshots. Test updated with a held-open negative case.
3. **Honest gap (open, not fixed)**: the 2–4k model reliably calls
   `redefine_chain`/`materialize` but does not connect `intent_call`
   failures ("intent not implemented") to wiring a meaning executor — a
   capability/prompt gap for J1.4, now visible per-decision in the pulse.

## 6. Acceptance status

- [x] J1.5.1 attempt budget (F1) — scripted + incident replay §3
- [x] J1.5.2 round-budget semantics (F2) — scripted + regression guard
- [x] J1.5.3 WorldInspector/FlightRecorder (F3) — §2 cost + §5 live catch
- [x] J1.5.4 HarnessProfilerView — 3 widget tests, analyze clean
- [x] J1.5.5 driver wiring — pulse + dump on exit/SIGINT, both runs
- [x] J1.5.6 backend-error budget (found *by* the monitor) — fixed + tested
- [ ] **J1.4 AFM gate (pass@3 ≥ 1/3)** — open; blocker is now precisely
      diagnosed (meaning-executor wiring), no longer an observability blind
      spot. The escalation ladder (J7/J8) is the next lever.
