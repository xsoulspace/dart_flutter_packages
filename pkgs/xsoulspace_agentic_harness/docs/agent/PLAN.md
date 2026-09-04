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
from a pi transcript), **#2 the overhead row** (the meaning-profile
surface is 1408 fixed tokens — fits the AFM window with 2392 working
memory left), **#3 the capture loop** (novel resolution → project pack →
reuse at zero authored tokens), **#4 the remote mover** (the daemon runs
MODEL-LESS; the client's model decides via `session/propose_move`), and
**#5 the persistent daemon** (single-instance, warm attach, keep-warm,
AOT composes with native assets), **#6 R7e** (**pass@3 = 3/3 — a real
on-device AFM model performed a real pack-fed edit through the surface,
2,008 tokens/decision**) and **#7 the real-model pi row** (**PASS —
pi's model drove the MODEL-LESS daemon via `session/propose_move`, 8
decisions = 8 round-trips**). THE PRODUCTION PATH IS COMPLETE — every
gate has a published row; the follow-ups are in the ledger below.

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
4. **~~Remote mover / actor registration~~ — DONE (production #4).** The
   daemon runs MODEL-LESS: every decision round-trips to the client as
   `session/propose_move` (bounded cut + tool schemas out, typed tool
   calls back; decisionId echo-checked; the ACP toolkit gained the
   `AcpMoveProposing` capability, symmetric with `request_permission`).
   Gate was green (LLM-free): one decision = one propose_move;
   budgets consumed in-world; cancel mid-decision works
   ([results_r7.md](results_r7.md)).
5. **~~Persistent daemon + AOT~~ — DONE (production #5).** Single-instance
   per workspace (exclusive lock; a second daemon exits 2), warm attach
   over a unix socket (second session continues ONE world — measured
   ~0–1 ms startup, zero re-scan), keep-warm with idle-exit, and AOT
   composes with the native-assets hook (no fallback needed)
   ([results_r7.md](results_r7.md)).
6. **~~R7e — THE GATE~~ — DONE (production #6): pass@3 = 3/3.** The REAL
   on-device AFM model performed the pack-fed edit through the
   meaning-profile surface in ONE decision (2,008 tokens — 45% of the
   window). The failing runs found the predicted failure classes and the
   surface was tuned (never the law): `symbolId` is the ONE REQUIRED id
   (optional slots get dropped by the 2–4k model — measured),
   `executableParams.symbolId` is promoted (the wire declares the slot),
   `label` resolves mechanically with ambiguity bounces
   ([results_r7.md](results_r7.md)).
7. **~~Real-model pi row~~ — DONE (production #7): PASS.** The MODEL-LESS
   daemon (`--remote-mover`), pi's real model answering propose_move with
   tools built VERBATIM from the proposal schemas: 8 decisions = 8
   round-trips, the pack edit landed with an id the model self-corrected
   from the cut. Findings shipped: pi prompts are SERIALIZED (proposals
   land mid-turn), the schema bundle's `root` wrapper must be unwrapped
   client-side, and the meaning profile's `run` tool is a WRITE HOLE
   (`perl -pi` reached the file — follow-up in the ledger)
   ([results_r7.md](results_r7.md)).

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
  the ENTIRE production path LANDED 2026-09-04 (#1 edit surface, #2
  overhead row, #3 capture loop, #4 remote mover, #5 persistent daemon,
  **#6 R7e pass@3 = 3/3 on real AFM**, **#7 real-model pi row PASS**).
- **R8 — last_answer hosts the harness (ADR 0015, TASK B): LANDED
  (LLM-free).** The app's first embedded domain host:
  `lastanswer/lib/coding_agent/` owns the daemon lifecycle IN-PROCESS
  (`HarnessAcpBackend` + `AcpStdioServer` over an in-memory duplex
  channel + `AcpClient`); per-workspace worlds/snapshot stores stay
  backend-owned. The user is an actor: task input = host-injected
  decision (`session/prompt`), approvals ride the EXISTING
  `session/request_permission` round-trip — no second protocol. UI:
  task sentence + workspace, session list, streamed progress,
  permission allow/reject, verdict banner. Gate: LLM-free scripted e2e
  green in the app's own suite — delegate → permission (allow) →
  `verdict: PASS` + write lands; delegate → permission (reject) →
  write never lands, `verdict: FAIL`; host lifecycle (start/stop,
  per-workspace session continuation, snapshot store). Real backends
  ride the same surface behind the config flag.
  **Backend switch (AFM ↔ OpenRouter) LANDED:** UI segmented control →
  `HarnessSessionController.switchBackend` restarts the daemon;
  per-workspace snapshot stores restore the world on the next session
  (R7c `loadSession` — proven scripted: switch mid-workspace, second
  turn PASSes on the restored world). OpenRouter keys come from the UI
  field or `OPENROUTER_API_KEY`; an unresolvable key is an honest
  pre-session config error, never a mid-turn crash.
  **AFM e2e gate GREEN (2026-09-04, macOS 26.6.2, real app):**
  `flutter test integration_test/coding_agent_afm_e2e_test.dart -d macos`
  — real on-device fixture fix through the embedded daemon:
  `verdict: PASS` (1 decision, 3 rounds, 1,360 projection tokens,
  31.8 s wall; moves read → declare_check → write; lean profile).
  Known constraint: the Flutter app cannot resolve the bridge code asset
  yet (SDK 3.12, no `DynamicLibrary.codeAsset` in Flutter builds) — the
  gate passes `XS_FM_BRIDGE_PATH` to the hook-built dylib. Follow-up:
  bundle the dylib in the Runner build phase.
  Product boundary: the agent-doc model, topology rules and the
  composition law are owned by the product — last_answer
  `docs/decisions/0003-agents-live-in-docs.md`. Two OPEN problems that
  belong HERE (product-agnostic, pulled by that direction): (a) **actor
  topology** — 1 world/N actors (squad, proven) vs N worlds/1 brain
  (remote mover, proven) vs mixed; which topology a task uses is task-
  and CLI-dependent DATA, no engine yet; (b) **multi-workspace daemon** —
  one process hosting several worlds (one per workspace, Zed/monorepo
  parity) with per-workspace single-instance locks unchanged.

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
- [x] Remote mover / actor registration (production #4) — DONE
      2026-09-04; [results_r7.md](results_r7.md).
- [x] Persistent daemon + AOT (production #5) — DONE 2026-09-04
      (single-instance, warm attach, keep-warm, AOT composes);
      [results_r7.md](results_r7.md).
- [x] R7e gate: one real AFM edit through the daemon, pass@3 (production
      #6) — DONE 2026-09-04, **3/3**; [results_r7.md](results_r7.md).
- [x] Real-model pi row (production #7, model-less daemon — pi's model
      answers propose_move) — DONE 2026-09-04, **PASS**;
      [results_r7.md](results_r7.md).
- [ ] Constrain the meaning profile's `run` tool to the convention
      commands (analyze/test/run — no file-mutating flags): the pi row
      found `perl -pi` as a write path (law violation surface).
- [ ] Unwrap the schema bundle's `root` wrapper server-side (the pi row
      client works around it today).
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner
  subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** —
  drive a *running* Flutter app (semantic snapshots, tap, hot-reload)
  through one MCP tool surface; the harness sees the same `intent_call`
  shape over a transport adapter (D5). Unblocks after the edit-tier loop
  proves on-device.
