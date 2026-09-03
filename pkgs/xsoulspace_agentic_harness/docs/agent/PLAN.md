# Agent Harness — Plan (THE RACE: real dogfooding, head-to-head numbers, migration)

> Forward/frontier record only. All landed work (A–I, J/K, M, N, P, R6, R7)
> lives in [history.md](history.md); durable decisions in the
> [ADR Index](../../../../docs/decisions/README.md); benchmark rows in
> `results_*.md` (current: [results_r7.md](results_r7.md)). The coding
> pipeline end-to-end: [pipeline_coding.md](pipeline_coding.md).
>
> House rule for this plan: **the coding agent IS the coding agent.** Issues
> in its own packages are its backlog, delegated to its own actors. pi
> orchestrates and escalates; pi does not absorb fixes the harness can do.

## NOW — the production path (what stands between here and AFM production)

Everything below is ordered; each item names its gate. The R7 machinery
(edit tier, daemon, packs) is landed and LLM-free-gated — see
[results_r7.md](results_r7.md). What is NOT yet true: **no real model has
ever driven the edit surface**, and pi can only rename.

1. **Full edit surface over ACP (blocks everything else).** pi can only
   reach rename today: the extension's `harness_edit` maps to the
   scripted mover's `[rename old new]` directive, so `insert_member` and
   `replace_member_body` — the two model-composed moves of R7b — are
   unreachable from the outer agent. Replace the prose directive protocol
   with a STRUCTURED tool contract: `harness_edit` carries the exact
   `edit_symbol` args (action, symbolId, opChain, executableId, params).
   Gate: the pi driver performs an insert + a body replacement through
   the transcript.
2. **Meaning-profile overhead vs the AFM window (mechanical, unblocks
   R7e).** Measure system prompt + 5 tool schemas + cut against the ~4k
   window with the P1 pre-flight guard (`maxContextTokens`). `edit_symbol`
   is the largest schema in the registry — never measured. Gate: a row in
   results_r7.md with the honest overhead number.
3. **Packs as the PRIMARY path.** AFM measured 0/3 hand-writing VM
   assembly; R7d's answer (the model supplies ids, the pack carries the
   chain) exists as one worked example with NO inventory and NO capture
   loop. Production readiness = the model rarely composes op-chains:
   wire the ADR 0021 capture loop (novel resolution → pack entry) to the
   edit tier. Gate: a novel scripted resolution becomes a pack entry and
   the next task costs zero authored tokens.
4. **R7e — THE gate: one real AFM edit through the daemon, pass@3.** In-app
   (in-process, not stdio) → meaning-profile edit → `dart analyze` + the
   workspace convention green. Everything above exists to make this run
   measurable. This is the last open race track.
5. **First real-model pi row (after 1–2).** One real-model session, pi →
   daemon, fixture task — publish the row even if it FAILS. The failure
   class (schema size? slot ambiguity? cut composition?) decides whether
   we tune the surface or the model tier. Worth more than any further
   scripted hardening.

Interactive hygiene (parallel, small): mid-turn streaming of tool results
(today they land at run end — a 30–60s silent tool call reads as a hang);
skip the turn-grade when no move applied and the baseline is cached-green;
wire pi's consent UI to `session/request_permission` (the gate driver
auto-answers today).

Architecture next (both shrink latency and unify ownership — record now,
build after #1):

- **Remote mover / actor registration.** pi stops delegating task cycles
  and JOINS as the session actor's brain: the daemon runs the loop, pi is
  the GenerationHandler (server→client `session/propose_move`: bounded cut
  + tool schemas out, typed tool calls back — same pattern as
  `session/request_permission`). Kills the per-call task cycle (~23s
  grades → ~1 model call), unifies budgets/consent/cancel inside the
  world, keeps the law (host still validates + materializes everything;
  pi never touches files). Seam exists: `handlerFactory` / `--scripted`
  already prove the mover is pluggable.
- **Persistent daemon + AOT.** `dart compile exe bin/harnessd.dart`
  (VERIFY with the native-assets hook — the AFM bridge is a code asset;
  fallback: AOT for open_router/scripted, `dart run` for AFM) + extension
  lifecycle: pid/lock file under `<workspace>/.dart_tool/harnessd/`,
  connect-if-live / spawn-if-absent / keep-warm on session end. Two
  daemons on one workspace break single-writer at the process level —
  single-instance is mandatory. Snapshot store becomes crash recovery
  only.

## Proven (runtime-verified, not asserted)

- Flat tokens/decision at scale — legacy projection 1.07×, composed cut
  flat over 300 decisions (`long_horizon_composition_test.dart`), and the
  repo-scale ETL verdict: 11,590 nodes / 67,444 edges, ETL-out fidelity
  10,649/10,649, cuts FLAT vs tier 1 (2,044 tokens local at both tiers),
  cuts 4–61ms ([results_etl_scale.md](results_etl_scale.md)).
- The edit tier exists and is gated: `edit_symbol` with the three fences,
  auto-revert with failure attribution, zero `read`/`write` moves; the
  daemon persists beats/verdicts/budgets per workspace and re-derives the
  tree ([results_r7.md](results_r7.md)).
- On-device AFM coding: bugfix_01 pass@3 = 3/3 post-fixes (P1 closed).
- Delegation loop end-to-end: pi → CLI/daemon → world → verdict →
  evidence (`benchmark/runs/delegation_m1_evidence.md`).
- Multi-actor squad, single-writer locks, per-actor verification, roles,
  a2a columns, analyzer board, replay miner + seeder: all LLM-free proven.
- M0b `declare_check`: model-proposed criteria as data, host-validated,
  mechanically executed.

**NOT proven (the remaining race):** the head-to-head (R3) pi column; a
real-model edit through the daemon (R7e); flatness claims on a real-model
session through the new surface; pack inventory + capture loop (R7d).

## Race tracks (each ends in a number or a live artifact)

- **R1 — self-improvement loop:** SUPERSEDED by ADR 0021 (problems as
  canonical rows, project-guided packs, source-analyzer oracle). Landed:
  `problem_board.dart` — 7/7 LLM-free tests incl. real `dart analyze`
  oracle and revert. Follow-up: capture-loop wiring to the EDIT tier (see
  production path #3).
- **R2 — flatness WITH composition:** DONE. The claim survives the working
  set (`long_horizon_composition_test.dart`).
- **R3 — head-to-head numbers:** harness columns ran; scripted tier delta
  published. The ONLY unexecuted piece is the real-model pi column — see
  production path #5.
- **R4 — large-model profile:** DONE. `coderLarge()`/`coderLean()` declared;
  1.32× graceful scaling, zero overflows.
- **R5 — editor live:** DONE. `benchmark/runs/r5_acp_session_transcript.txt`.
  The R7 daemon work supersedes its write-gate-only contract (tool results
  now stream too).
- **R6 — workspace-oracle meaning tier:** DONE (first track). The R6 gate:
  1 decision, 7,857 projection tokens, `dart test exit=0`, zero model code
  tokens, zero host-authored expectations ([results_r6.md](results_r6.md)).
- **R7 — edit-as-re-derivation:** a/b/c/d LANDED + gated (see history);
  **R7e (real AFM edit through the daemon) is the open track — production
  path #4.**

## Standing rules

- Every published number states backend, decision path, tokens source,
  tool surface, and n. Failures are data (classified, never dropped).
- Escalation-rate breakdown ships beside every pass-rate table.
- Gravity: tiny model stays useful; fewer LLM calls; context bounded+derived
  (D7: harness-owned); LLM-free testable. `expectIdle` ends every test.
- The model never writes code tokens, never sees an AST, never holds the
  whole tree. Materialization, verification, projection, macros,
  decomposition, repair = pure host programs (`Agent = G ∘ F`).
- No AE embed; no transport protocols in core; no domain materializers in
  core (ADR 0015). Plans are data, never prose.
- The filesystem is a projection target, never the actor's interface (ADR
  0023): `read` → zoom, `write` → edit move. Whole-file `write` is
  LEGACY-HOST-ONLY.

## Cleanup / hard-cut ledger

- ~~Collapse overlapping edit paths; delete~~ — DONE 2026-09-01 (B4);
  [history.md](history.md).
- ~~Delete legacy manual-schedule tests~~ — DONE 2026-09-01 (B5).
- ~~Docs cleanup: superseded briefs/plan docs moved to [archive/](archive/)~~
  — DONE 2026-09-03 (ADR-referenced docs kept in place; links fixed).
- [ ] Structured `harness_edit` tool contract over ACP (production #1).
- [ ] Meaning-profile overhead row vs the AFM window (production #2).
- [ ] Edit-tier capture loop → pack inventory (production #3).
- [ ] R7e gate: one real AFM edit through the daemon, pass@3 (production #4).
- [ ] Real-model pi row through the daemon (production #5).
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner
  subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** —
  drive a *running* Flutter app (semantic snapshots, tap, hot-reload)
  through one MCP tool surface; the harness sees the same `intent_call`
  shape over a transport adapter (D5). Unblocks after the edit-tier loop
  proves on-device.
