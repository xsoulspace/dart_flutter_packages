// ignore_for_file: lines_longer_than_80_chars

/// P-series results — the pragmatic path (P1 bridge, P2 overseer, P3 host
/// write gate + git projections, P5 persistent sessions, P6 NDJSON).
/// LLM-free (scripted backends) unless marked on-device (AFM).

# P-series results (2026-09-01)

Acceptance evidence for the P-series mission. Sources: on-device pass@3
logs in `../xsoulspace_inference_apple_foundation/benchmark/runs/` (copied
run logs `coding_agent_afm_run*.log` + `coding_agent_afm_summary.log`),
the scripted CI tests (`overseer_scripted_test.dart`,
`coding_agent_scripted_test.dart`, `fs_tools_test.dart`,
`persistent_resume_test.dart`, `native_bridge_test.dart`), and the Swift
bridge regression suite (`bridge/tests`, 26/26 incl. live sessions). Every
number states backend, decision path, tokens source, tool surface, and n.

## 1. P1 — bridge cancel contract (the two crashed pass@3 sets, fixed)

**Crash mechanism (traced + fixed).** On a Dart-side `generation_timeout`,
the client closed its `NativeCallable.listener`s while the Swift side still
held pending tool continuations and the generation task — the next callback
invocation landed on freed trampolines (VM crash). Fix, both sides:

- Swift: a per-generation state + registry gates EVERY callback path
  (done/tool-payload/stream-delta) behind one lock; `xs_fm_cancel(gen_id)`
  claims the gate, resumes pending tool continuations with a structured
  cancellation error, cancels the Swift task, and permanently no-ops all
  callbacks for that generation. `xs_fm_generate_async` now returns the
  generation id (>0 accept / -1 immediate failure); payloads carry
  `{"generation": id}`; `xs_fm_abi_version()` = 2 lets Dart detect stale
  dylibs (missing symbols degrade to logged no-ops instead of lookup
  crashes).
- Dart: on timeout the client calls `cancelGeneration(genId)` BEFORE any
  teardown; a per-call `_activeGeneration` guard drops any payload from a
  foreign (cancelled) generation; timeouts return a STRUCTURED error
  (`generation_timeout`, `meta.cancelled: true`).

| Proof | Result | Source |
|---|---|---|
| Swift unit + live bridge tests | **26/26 PASS** (incl. cancel-gate + 8 live AFM sessions) | `sh tool/check_bridge_swift.sh` |
| Dart fake-bridge tests (no dylib) | timeout → structured error + cancel recorded BEFORE teardown; stale done payload after cancel → harmless; subsequent generate succeeds; structured context-window error propagates | `native_bridge_test.dart` |
| Stale-dylib tolerance | pre-cancel dylib loads with a WARNING (cancel no-op) instead of a hard `dlsym` crash | optional symbol lookup, `bindings.dart` |

### First valid post-B1 intent-tier measurement (n=3, zero infra deaths)

backend: `apple_foundation_afm` (Apple Foundation Model, 4k window); path:
`bin/coding_agent.dart --task intent_03_bookmark_macros --runs 3`; tokens
source: Situation.tokensUsed per decision, summed; surface: intent tooling
(intent_define/act_with_project/intent_call); fresh jail per run.

| Task | Arm / oracle | n | pass@n | decisions/run | moves/run | tokens/run | overflows | bridge crashes | verdict |
|---|---|---|---|---|---|---|---|---|---|
| intent_03_bookmark_macros | intent-graded (verifier in-loop + dart oracle final gate) | 3 | **0/3** | 9, 3, 9 | 68, 8, 46 | 20,517 / 6,319 / 19,140 | 0 | **0** | **GATE FAIL — honest; infra FIXED** |

The two previous pass@3 attempts died mid-run to the bridge crash (never
producing an n); this set COMPLETED — every budget held, every run
terminated idle, zero context overflows, zero bridge crashes. Honest
verdict: the op-localized return-error fix now has completed n; the
remaining blocker is chain-logic correctness (P2's target).

## 2. P2 — J7 overseer (scripted green; on-device n=3)

**Landed** (`lib/src/tooling/overseer.dart` + the policy widening in
`build_gates.dart`): when the mover exhausts its goal budget, an overseer
actor spawns with a brief containing ONLY (a) the summary zoom
(`meaningCut(zoom: 'summary')`), (b) the structured gate failure, (c) the
failing intent's chain dump (validateMeaningProgram problems + chain ops +
an interpreter replay of the failing call). Closed vocabulary via ONE tool
(`overseer_decision`): `approve` / `repair(intent, notes)` /
`escalate(reason)`. `repair` re-opens exactly that intent's scope via
`openFreshDecision` on the MOVER (notes prepended, max 1 cycle; the
RunGradedGoalPolicy allowance widens monotonically — base × (1 + cycles),
never a reset). `approve` never forces a pass (the mechanical final oracle
still grades); `escalate` swaps to a higher `Model.tier` if the router
declares one, else structured FAIL.

### Scripted proof (LLM-free, through the SAME driver the AFM runs use)

`overseer_scripted_test.dart`: the mover builds the measured on-device
failure class (swapped branch literals → `save_url` returns
`{saved: false}` for a valid url), exhausts the budget, the overseer
receives the brief (asserts: summary zoom present, `intents failed:
save_url` in the gate failure, the chain dump with op rows), emits
`repair(save_url)` with op-specific notes, the mover re-defines the chain
correctly, and the final gate goes green (`all 4 calls verified`).
Exactly one disposition; world idle. **PASS.**

### On-device (pass@3 with the overseer live)

backend/path/tokens source as above. Numbers from
`/tmp/p2b_intent03_pass3.log` + `benchmark/runs/` (this session's gate):

| Task | n | pass@n | overflows | bridge crashes | verdict |
|---|---|---|---|---|---|
| intent_03_bookmark_macros | 3 | 0/3 | 0 | 0 | **GATE FAIL — honest** (overseer grants one repair cycle; a single model-side fix remains out of reach for the 2–4k model on the hardest failure class) |

Failures stay classified (return-without-empty-stack chains,
missing-executor builds); every run bounded and idle. The overseer's
escalation records ship in the run logs (ledger rows carry rung + reason).

## 3. P3 — host write gate + git projections (LLM-free)

Law-first note: the mission text proposed a model-visible
`writeMode: apply|dryRun` parameter — REJECTED in review as a violation of
"the model never writes code tokens" (the model would keep supplying
whole-file content). The landed design keeps the model surface UNCHANGED
and puts the policy in the host:

| Proof | Result | Source |
|---|---|---|
| Review gate: approved write lands, rejected write NEVER touches the disk; structured model ack | PASS | `fs_tools_test.dart` (JailWriteGateway group) |
| Unified diffs minimal, `/dev/null` for new files, per-write verdicts (APPLIED/REJECTED) | PASS | same |
| Apply mode byte-identical to the ungated path (default; zero behavior change) + host materializer writes flow through | PASS | same |
| `git_status`/`git_diff` reject outside a repo (`not_a_git_repo`); report branch/entries/diffs inside a temp git fixture; path-limited diff | PASS | same |
| End-to-end on a fixture git repo through the REAL driver: two scripted writes, one approved one rejected; approved fix lands, junk never does; audit ships diffs + verdicts | PASS | `coding_agent_scripted_test.dart` (P3 diff gate) |

CLI: `--diff-gate` (review mode) + `--auto-approve`; the write-gate audit
ships inside every per-run log (`--- write-gate audit (P3) ---`).

## 4. P5 — persistent sessions (LLM-free + CLI smoke)

| Proof | Result | Source |
|---|---|---|
| Restart survival: 2 moves → snapshot → world dropped → store restore → idle-resumable (no OpenDecision/Agency/AwaitingResponse), budgets persist (AttemptCount=2, ToolRoundCount=5), stale verdicts do NOT cross → one more decision → gate passes, world idle | PASS | `persistent_resume_test.dart` (harness) |
| Exclusions: OpenDecision/Agency/AwaitingResponse/LoopStuck/EscalationRequest/GoalVerified never materialize post-restore | PASS | `_excludedComponents`, `snapshot.dart` |
| CLI round trip: `--task … --scripted --jail … --session <store>` (PASS + `current.json` written) then `--resume <store>` (session meta restored: task + jail; re-verified green) | PASS | scripted runs, logged in this session |

## 5. P6 — NDJSON transport (documented + smoke-tested)

`coding_agent.dart --json` streams one JSON object per line on stdout:
`run_start` / `decision` (per generation turn, with tool calls from the
returned response — the native AFM path carries them; scripted runs show
`tool_calls: []` and a `responses_sent_delta` count) / `pulse` / `run_end`
(verdict, decisions, rounds, tokens, moves, gate details, failure class)
/ `summary`. Human lines move to stderr. The schema is documented in
`pipeline_coding.md` ("Host seams around the loop"). Smoke-tested: every
stdout line parses as JSON; event order and counts match the run log.

## 6. Honest non-claims

- **P4 is NOT landed** — `xsoulspace_agentic_dart_meaning` (analyzer
  round-trip, span-anchored edits) does not exist yet. The run-graded
  arm's whole-file `write` teaching prompt remains a NAMED law violation,
  scheduled for closure by P4; no new model-visible write surface was
  added this session.
- The intent-tier on-device gate (pass@3 ≥ 1/3) remains OPEN. The overseer
  repair cycle is scripted-proven but the 2–4k model did not convert it
  into a passing run within these 3 runs. Recorded as honest FAIL with
  classified blockers, never dropped.
- No single-run claims anywhere; every on-device number is pass@3 with
  per-run logs in `benchmark/runs/`.
