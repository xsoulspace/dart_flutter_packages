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

## NOW — the pi-dogfooding path (pi does the repo's real work THROUGH the harness daemon)

The production path (#1–#7) is COMPLETE — every gate has a published row
([history.md](history.md), [results_r7.md](results_r7.md)). The next
race is **turning the harness into pi's own work surface**: every
mutation pi makes to this repo — Dart code, Markdown docs, config and
asset files — routes through `harnessd`, so every mutation is
gate-checked (mechanical oracles), locked (single-writer), permission-
gated (the human allows), and logged (beats/verdicts). This is the
intent-first growth loop the law demands: pi's real work names the
surface gaps as structured failures, and the surface grows intent-first
— never vocabulary-by-hand.

Ordered work items (each names its gate):

1. **Constrain the meaning profile's `run` tool (P0, LAW-CRITICAL —
   DONE 2026-09-04).** `runTool` gained an argv-prefix `allowlist`
   (`dart analyze / dart test / dart run / flutter analyze / flutter
   test`); violations fail as named data (`command_not_allowed`) BEFORE
   spawning. Gate: `run_allowlist_test.dart` (harness pkg).
2. **Unwrap the schema bundle's `root` server-side (P0, DONE).** The
   remote mover now emits `parameters.root` — the client workaround is
   gone (measured in the pi row: the wrapper degraded every call).
3. **Filesystem verbs over ACP (P1).** Expose the core's read-only fs
   verbs (`list_dir`/`glob`/`grep` + jailed `git_status`/`git_diff`)
   plus whole-file write ONLY through the P3 `JailWriteGateway` in
   `review` mode (unified diff → `session/request_permission` → the
   human allows/rejects). Target: pi edits configs, YAML, scripts,
   assets — everything that is NOT Dart — through the daemon, audited,
   locked, and consent-gated. Gate: an fs-profile e2e (scripted) proves
   read → glob → grep → permission → write-lands; reject → never lands.
4. **Markdown meaning tier (P2).** Extend `repo_etl` to scan `.md`
   into the meaning tree (headings as section nodes, links as edges),
   one bounded prose move (`edit_doc` — whole-section replacement,
   host-spliced, never reflowing the whole file), and the MECHANICAL
   docs oracle: the 0-broken-links check (the docs workspace convention,
   D8). Prose is NOT code (ADR 0019): doc tasks grade through the docs
   oracle only — they can never `pass` a code gate, and code fences
   never apply to them. Gate: scripted doc-edit e2e — section replace
   lands, broken link bounces as named data, link-check green.
5. **Interactive remote mover in the pi extension (P3).** The gate
   driver script answers proposals; interactive `pi` must too: the
   extension hook answers `session/propose_move` with pi's configured
   model (the daemon stays the only file surface; pi never gets raw
   files). Gate: one real-model interactive session, pi → daemon, with
   the consent UI wired to `session/request_permission`.
6. **Actor-topology engine + multi-workspace daemon (P4, pulled by
   last_answer `docs/decisions/0003`).** The two proven topologies
   (1 world/N actors squad; N worlds/1 brain remote mover) become
   task-declared DATA with per-task topology selection; one process
   hosts several worlds with per-workspace single-instance locks.

Sequencing rule: P1 (fs verbs) before P2 (docs tier) — zoom-for-docs
needs the same read seam; the law-critical P0s are done. Detour stop:
any friction that blocks a pi task twice becomes a named failure class
in results_r7.md — the surface grows from those, not from guesses.

Interactive hygiene (parallel, small): ~~mid-turn streaming of tool
results~~ DONE (production #1 — a 40ms observer in `runCodingAgentOnce`
emits tool-result beats as they land); ~~skip the turn-grade when no move
applied and the baseline is cached-green~~ DONE (tiered verification —
`VerifyTierPlanner`, see Proven); REMAINING: wire pi's consent UI to
`session/request_permission` (the gate driver auto-answers today).

Surface ergonomics (host program, the intentcall/mcp_flutter registry
lesson — P0.5, NOT STARTED): registration-time validation of tool
surfaces — a linter over `ToolDef`s enforcing the R7e rules (required
anchor slots declared on the wire, mechanical label resolution,
bounces carry repairs) so ANY model — tiny or large — gets a
convenient, uniform surface. Materializer specs stay data (ADR 0023):
`{span currency, map format, emitter, oracle}` per file type — md and
dart today, more later — so new materializations register, never fork.

## Proven (runtime-verified, not asserted)

- **Tiered verification is HARNESS machinery (2026-09-04).** The 20–23s
  full-suite grade after every tool round is fixed in the harness, not
  the host: `VerifyTierPlanner` (stateless, derives "edits pending since
  the last `goal_verify` beat" purely from thread beats — no side-channel
  counters, snapshot-safe) + `VerifyConvention` as DATA (edit-beat names,
  test-scope prefixes, narrow-command template). The verifier writes a
  `goal_verify` beat per grade, so grades are graph state visible to
  projection/metrics. Hosts contribute conventions as data —
  `dartVerifyConvention` (`edit_symbol`, `test/`, `dart test <files…>`);
  a future rust/ts host supplies its own ETL + convention and changes
  nothing else (intentcall registry pattern: canonical contract upstream,
  mechanical resolution; a convention registry resource graduates only
  when a second stack coexists). Gate: `verify_tier_planner_test.dart`
  (harness pkg) — skip → narrow (real `runGoalVerifier` grade path) →
  full fallback.
- Flat tokens/decision at scale — legacy projection 1.07×, composed cut
  flat over 300 decisions (`long_horizon_composition_test.dart`), and the
  repo-scale ETL verdict: 11,590 nodes / 67,444 edges, ETL-out fidelity
  10,649/10,649, cuts FLAT vs tier 1 (2,044 tokens local at both tiers),
  cuts 4–61ms ([results_etl_scale.md](results_etl_scale.md)).
- The edit tier is CLOSED under the law AND proven on real models:
  `edit_symbol` with the three fences, auto-revert with failure
  attribution, zero `read`/`write` moves; the daemon persists
  beats/verdicts/budgets per workspace and re-derives the tree
  ([results_r7.md](results_r7.md)).
- On-device AFM coding: bugfix_01 pass@3 = 3/3 post-fixes (P1 closed);
  R7e (pack-fed edit through the daemon surface) pass@3 = 3/3.
- Delegation loop end-to-end: pi → CLI/daemon → world → verdict →
  evidence (`benchmark/runs/delegation_m1_evidence.md`).
- Multi-actor squad, single-writer locks, per-actor verification, roles,
  a2a columns, analyzer board, replay miner + seeder: all LLM-free proven.
- M0b `declare_check`: model-proposed criteria as data, host-validated,
  mechanically executed.

**Open race (the dogfooding path, §NOW above):** pi's whole tool surface
through the daemon (fs verbs, docs tier, interactive remote mover,
topology engine).

## Race tracks (each ends in a number or a live artifact)

- **R1 — self-improvement loop:** SUPERSEDED by ADR 0021 (problems as
  canonical rows, project-guided packs, source-analyzer oracle). Landed:
  `problem_board.dart` — 7/7 LLM-free tests incl. real `dart analyze`
  oracle and revert. Capture-loop wiring to the EDIT tier: DONE
  (production #3 — see history).
- **R2 — flatness WITH composition:** DONE. The claim survives the working
  set (`long_horizon_composition_test.dart`).
- **R3 — head-to-head numbers:** DONE — the real-model pi column ran
  (production #7: pi's model drove the MODEL-LESS daemon; row published).
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
  `docs/decisions/0003-agents-live-in-docs.md`. **Phase 1 LANDED
  (2026-09-04):** the doc surface (`formatId: 'agent'`, AgentDocModel
  payload, AgentDocSurface in ProjectView, MCP/intent entries) plus
  `HarnessAcpBackend(checkCommand:)` — the doc binding's declarative
  `--check`. Self-profile gate GREEN: an agent doc bound to last_answer
  itself fixed a committed failing fixture on-device (AFM), graded by an
  oracle that fails until the agent acts (rows + dogfooding findings in
  `benchmark/runs/delegation_m1_evidence.md`). Two OPEN problems that
  belong HERE (product-agnostic, pulled by that direction): (a) **actor
  topology** — 1 world/N actors (squad, proven) vs N worlds/1 brain
  (remote mover, proven) vs mixed; which topology a task uses is task-
  and CLI-dependent DATA, no engine yet; (b) **multi-workspace daemon** —
  one process hosting several worlds (one per workspace, Zed/monorepo
  parity) with per-workspace single-instance locks unchanged; (c) from
  the Phase-1 dogfood: **new-task goal isolation on a resumed world** —
  the per-workspace store carried the previous goal and the small model
  replayed it.

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
- [x] Constrain the meaning profile's `run` tool to the convention
      commands (analyze/test/run — no file-mutating flags) — DONE
      2026-09-04 (`run_allowlist_test.dart`); found by the pi row.
- [x] Unwrap the schema bundle's `root` wrapper server-side — DONE
      2026-09-04 (the remote mover emits `parameters.root`).
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner
  subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** —
  drive a *running* Flutter app (semantic snapshots, tap, hot-reload)
  through one MCP tool surface; the harness sees the same `intent_call`
  shape over a transport adapter (D5). Unblocks after the edit-tier loop
  proves on-device.
