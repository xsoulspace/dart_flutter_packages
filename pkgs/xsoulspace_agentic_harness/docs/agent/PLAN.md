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
[results_r7.md](results_r7.md). Landed on the path: **#1 the full edit
surface over ACP** (the structured `harness_edit` contract —
`insert_member` + `replace_member_body` + `apply_executable` all driven
from a pi transcript) and **#2 the overhead row** (the meaning-profile
surface is 1408 fixed tokens — fits the AFM window with 2392 working
memory left). What is NOT yet true: **no real model has ever driven the
edit surface**, packs have no capture loop, and pi still delegates whole
task cycles.

1. **~~Full edit surface over ACP~~ — DONE (production #1).** The prose
   directives (`[rename old new]`) are gone: `harness_edit` carries the
   exact `edit_symbol` args as a structured JSON payload; the mover
   executes verbatim and never guesses ids. Gate was green: the pi driver
   transcript performs an insert + a body replacement (+ rename) with
   analyze + workspace convention green
   ([results_r7.md](results_r7.md), [transcript](../../benchmark/runs/r7_edit_surface_transcript.txt)).
2. **~~Meaning-profile overhead vs the AFM window~~ — DONE (production
   #2).** Measured: 1408 fixed tokens (system 141 + 5 schemas,
   `edit_symbol` largest at 594) vs the P1 guard (3800) — the surface
   FITS; only the cut is a free parameter
   ([results_r7.md](results_r7.md)).
3. **~~Packs as the PRIMARY path~~ — DONE (production #3).** The ADR 0021
   capture loop is wired to the edit tier: a model-composed
   `replace_member_body` that passed all fences + oracles becomes a
   registered `EditExecutableWire` + op-chain (`registerPackExecutable`),
   persisted in the project pack (`.dart_tool/harnessd/edit_pack.json`,
   mechanical fingerprint id); every `edit_symbol` auto-realizes the
   pack. Gate was green: scripted novel resolution → pack entry → a
   second task consumes it at ZERO authored tokens
   ([results_r7.md](results_r7.md)).
4. **Remote mover / actor registration (the precondition for #7).** pi
   stops delegating task cycles and JOINS as the session actor's brain:
   the daemon runs the loop, pi is the GenerationHandler. Server→client
   `session/propose_move` (same JSON-RPC pattern as
   `session/request_permission`): bounded cut + tool schemas out, typed
   tool calls back. Kills the per-call task cycle (~23s grades → ~1 model
   call); budgets/consent/cancel become native to the world. Seam exists:
   `handlerFactory` / `--scripted` prove the mover is pluggable. Bounded
   protocol only — pi never gets raw files. Gate: a scripted
   client-as-mover test (LLM-free) proves one decision = one
   `propose_move` round-trip; budgets consumed in-world; cancel
   mid-decision works.
5. **Persistent daemon + AOT.** (a) `dart compile exe bin/harnessd.dart`
   — VERIFY it composes with the native-assets hook (the AFM bridge is a
   code asset); fallback: AOT for open_router/scripted, `dart run` for
   AFM. (b) Extension lifecycle: pid/lock file under
   `<workspace>/.dart_tool/harnessd/` → connect-if-live (initialize
   health ping) / spawn-if-absent / keep-warm on session_end (idle-exit
   after N minutes). SINGLE-INSTANCE PER WORKSPACE IS MANDATORY (two
   daemons = two worlds = single-writer broken at process level). Snapshot
   store demotes to crash recovery only. Gate: a second pi session
   attaches to the warm daemon — zero re-scan (mechanical refresh tick
   only), startup < 2s.
6. **R7e — THE GATE: one real AFM edit through the daemon, pass@3.**
   In-process (not stdio) from the AFM app: meaning-profile surface, one
   fixture edit (use the pack path from #3), `dart analyze` + the
   workspace convention green. Everything above exists to make this run
   measurable. If the overhead row (#2) ever stops fitting, cut the
   surface first (lean schemas), never the law.
7. **Real-model pi row (SCOPE FIXED 2026-09-04 — the pi column has NO
   daemon mover).** The daemon under test runs MODEL-LESS: pi's own real
   model is the session actor's brain via the #4 remote-mover protocol —
   wiring the daemon to open_router/AFM *while pi calls it* would put a
   second, worse model inside the loop and prove nothing about what we
   are actually testing: how the harness TOOL SURFACE behaves from pi's
   perspective (flows, latency, ergonomics) against pi's native tools.
   Production movers (AFM on-device, open_router for the coding CLI /
   general agent) are a SEPARATE track — the `--scripted`/`--remote-mover`
   split exists exactly so the surface gate never depends on a mover
   model. Gate: one real-model pi session, pi → daemon (remote mover),
   fixture task via `run_r7_daemon_gate.mjs` with pi on a real provider —
   publish the row even if it FAILS; classify the failure (schema size?
   slot ambiguity? cut composition?).

Interactive hygiene (parallel, small): ~~mid-turn streaming of tool
results~~ DONE (production #1 — a 40ms observer in `runCodingAgentOnce`
emits tool-result beats as they land); REMAINING: skip the turn-grade
when no move applied and the baseline is cached-green; wire pi's consent
UI to `session/request_permission` (the gate driver auto-answers today).

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

**NOT proven (the remaining race):** the head-to-head (R3) pi column;
a real-model edit through the daemon (R7e); flatness claims on a real-model
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
  production #1 (full edit surface over ACP), #2 (overhead row) and #3
  (capture loop → pack inventory) LANDED 2026-09-04; **R7e (real AFM
  edit through the daemon) is the open track — production path #6.**

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
- [x] Structured `harness_edit` tool contract over ACP (production #1) —
      DONE 2026-09-04; [results_r7.md](results_r7.md).
- [x] Meaning-profile overhead row vs the AFM window (production #2) —
      DONE 2026-09-04 (1408 fixed tokens; fits); [results_r7.md](results_r7.md).
- [x] Edit-tier capture loop → pack inventory (production #3) —
      DONE 2026-09-04; [results_r7.md](results_r7.md).
- [ ] R7e gate: one real AFM edit through the daemon, pass@3 (production #4).
- [ ] Real-model pi row through the daemon (production #5).
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner
  subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** —
  drive a *running* Flutter app (semantic snapshots, tap, hot-reload)
  through one MCP tool surface; the harness sees the same `intent_call`
  shape over a transport adapter (D5). Unblocks after the edit-tier loop
  proves on-device.
