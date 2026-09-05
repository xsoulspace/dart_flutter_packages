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

## Open issues & untested surface (honest ledger, 2026-09-06)

The race is REAL dogfooding — the surface below is built but not yet
proven by daily use. Working via harness for ALL files, dart + md first,
means closing this list.

### Open issues (named, unowned)

| Issue | Where | Next move |
|---|---|---|
| Double-spawn race in extension recovery (two spawns race → one client attaches to a dead socket) | `r7_harnessd_extension.ts` | serialize `ensureClient` behind a spawn promise (small TS fix) |
| Warm-tick floor ~1.4 s on the monorepo (full fs walk per tick for add/drop detection) | `fs_etl.dart` | tree-driven fs reconcile: stat from stored file nodes, walk only to catch adds |
| `harness_verify` unwired: the extension cannot pass a per-package `--check`; monorepo-root verify is meaningless | `harnessd_cli.dart` (`--check` exists) + extension env | wire `HARNESSD_CHECK` → spawn args; package-scoped verify |
| Root convention is a MONOREPO compromise (`flutter test` over root test/) — per-package tasks need per-package gates | `workspace_conventions.dart` | task sentences carry `--check` (the D8 convention stays the default) |
| Zoom staleness: cut props can lag a just-refreshed tree (mtime-reconciled nodes) | `meaning_query_tools.dart` | zoom re-stats the focus node (cheap) |

### Untested surface (built, never proven end-to-end)

| Feature | Gate that must run | Status |
|---|---|---|
| Consent plans (bounded grants, audit) | host unit tests green; NO real pi session has granted/audited one | unit-only |
| Reasoning beats (`thinking` capture, escalation reuse, `reasoning` hints) | scripted tests green; NO real-model run has exercised them | unit-only |
| `remove_member` (retire) on a REAL model flow | scripted gates green; no AFM/OpenRouter retirement attempt | unit-only |
| `harnessd --check` override | implemented this session, zero runs | untested |
| File-class registry extension path (register md/yaml/json `parse` fns) | registry unit-tested via tick; no non-dart class registered yet | path-only |
| md/yaml/json EDIT-side materializer specs (ADR 0024 §2 P2) | — | designed, not built |
| Pack work-orders (multi-edit consent-once work orders) | — | designed (ledger row), not built |
| Multi-workspace daemon (last_answer co-tenancy) | — | P4, not built |
| Refactor executables (`rename_package` packs) | — | designed (ledger row), not built |

### How to start working via harness for ALL files (the route)

1. **Dart** (works today): `harness_scan` → `harness_zoom`/`harness_impact`
   → `harness_edit` (replace/insert/remove/apply_executable) →
   `harness_verify`. Fences: coverage, expressiveness, integration, refs.
2. **md/yaml/json** (read today, edit via review gate): anchors are in the
   tree (zoom serves budgeted spans); writes route through
   `harness_fs_write` (consent) until each class's materializer spec lands.
3. **everything else** (`other`): visible in the tree, review-gated writes
   only — by design, never by omission.
4. **The extension of the surface itself** = register a file-class spec +
   materializer spec (see `xsoulspace_agentic_workspace/AGENTS.md`) — the
   same closed verb surface, more covered reality.

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
— never vocabulary-by-hand. **The gap ledger is
[surface_gaps.md](surface_gaps.md)** (opened 2026-09-06, seeded with the
ADR 0025/0026 session's honest escapes): every bash escape appends a row
(what bash did, why the surface didn't cover it, the verb/spec to build);
gaps close as materializer specs / surface verbs — the same tools must
later serve the 2–4k AFM model, for whom raw bash does not exist.

Ordered work items (each names its gate; the fs tier follows ADR 0024
[filesystem as one map-graph — typed materializer specs, uniform edit
verbs, tiny-model-first surfaces]):

1. **Constrain the meaning profile's `run` tool (P0, LAW-CRITICAL —
   DONE 2026-09-04).** `runTool` gained an argv-prefix `allowlist`
   (`dart analyze / dart test / dart run / flutter analyze / flutter
   test`); violations fail as named data (`command_not_allowed`) BEFORE
   spawning. Gate: `run_allowlist_test.dart` (harness pkg).
2. **Unwrap the schema bundle's `root` server-side (P0, DONE).** The
   remote mover now emits `parameters.root` — the client workaround is
   gone (measured in the pi row: the wrapper degraded every call).
3. **Filesystem tier v1 — one map-graph + escape hatch (P1, ADR 0024 —
   DONE 2026-09-05, with the Amendment: the escape hatch's READ side is
   retired; text enters ONLY as budgeted span cuts under meaning
   anchors).** `repo_etl` indexes dir/file nodes for EVERY file plus the
   md/yaml/json map half (section/keypath anchors) in one mechanical
   pass; `meaning_zoom` point cuts serve anchor spans (budgeted); mapless
   classes mutate only through `write_review` (review-gated, deny-by-
   default). Gate: fs-tier e2e — map-read → zoom → consented review
   write lands; reject → never lands (`harnessd_fs_tier_test.dart`).
4. **Markdown materializer (P2, first non-dart spec).** The md spec as
   data (`{span: heading section, map: headings+link edges, emitter:
   whole-section splice, oracle: 0-broken-links}`, D8 docs convention);
   `edit_doc` in the uniform verb shape (required anchor slot = section
   label, mechanical resolution, bounce-with-repair). Prose is NOT code
   (ADR 0019): doc tasks grade through the docs oracle only — they can
   never `pass` a code gate, and code fences never apply to them. Gate:
   doc-edit e2e — section replace lands, broken link bounces as named
   data, link oracle green + the R7e tiny-model gate (ADR 0024 §5).
5. **YAML/JSON materializers (P2.5).** Keypath spans; offset-based
   splice (the `yaml` package does NOT round-trip comments —
   re-serialization forbidden); oracle = parse + intended-change
   semantic diff. Real-repo target: pubspec.yaml dependency bumps — a
   real pi task. Gate: yaml e2e (byte-level comment preservation) +
   tiny-model gate; json via stable re-serialization.
6. **Interactive remote mover in the pi extension (P3 — the LEGITIMACY
   blocker, co-critical with P1).** The gate driver answers proposals;
   real pi must too: the extension hook answers `session/propose_move`
   with pi's configured model (the daemon stays the only file surface;
   pi never gets raw files), and the consent UI is wired to
   `session/request_permission` — the scripted extension auto-allows
   and answers `{}`, which neutralizes deny-by-default and closes
   decisions model-less; that artifact must never be the thing pi works
   through. Gate: one real-model interactive session, pi → daemon,
   consent UI exercised.
7. **Actor-topology engine + multi-workspace daemon (P4, pulled by
   last_answer `docs/decisions/0003`).** The two proven topologies
   (1 world/N actors squad; N worlds/1 brain remote mover) become
   task-declared DATA with per-task topology selection; one process
   hosts several worlds with per-workspace single-instance locks.
8. **Seam purity (ADR 0026, DONE 2026-09-06).** The workspace host
   renamed to its true scope (`xsoulspace_agentic_workspace` — specs are
   data, md/json/text families land beside the registry, never a fork);
   the context-fragment protocol moved to `inference_core` (it defines
   core's `contextFragments` field) and the wire codec to the harness —
   openrouter is now a pure core-only client; the in-process ACP embed
   transport moved to the host (`HarnessEmbed`); stress scenarios moved to
   the harness. Anti-drift: the rejection list at the top of
   [pipeline_coding.md](pipeline_coding.md) + `pipeline.drift_check`.
9. **Reads are not builds (ADR 0027, DONE 2026-09-06).** The dogfood hot
   path: read-directive prompts execute mechanically (zero model, zero
   grade); free-form read delegations run as `readOnly` tasks (actor
   streams, gate stamped `read_only_not_applicable`); analyzer-before-tests
   fail-fast tier; `reasoning` policy on proposals + `thinking` capture
   (measured, never re-projected, reused on escalation); `mover_refusal`
   failure class; AOT-first + attach-if-live in the pi extension.
   Measured scripted + AFM: [results_seam_speed.md](results_seam_speed.md).

Sequencing rule: P1 (fs map-graph + escape hatch) and P3 (interactive
extension, consent UI) are CO-CRITICAL — pi working "through the daemon"
without consent is theater (the scripted extension auto-allows and closes
decisions model-less). Then P2 (md materializer), P2.5 (yaml/json) —
zoom-for-docs needs the same read seam. The law-critical P0s are done.
Detour stop: any friction that blocks a pi task twice becomes a named
failure class in results_r7.md — the surface grows from those, not from
guesses. Every new materializer lands with an R7e tiny-model gate
(ADR 0024 §5).

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
  **Phase 1.5 (the HUMAN gate) GREEN (2026-09-05, product side):** the
  dylib is bundled in the app's Runner build phase (no `XS_FM_BRIDGE_PATH`);
  the GUI loop ran on the last_answer repo itself — findings that belong
  HERE (pull, do not absorb): (a) an unanswered `session/request_permission`
  stalls the write tool for its full 5-minute deadline and the model
  retries into another 5-minute wait — the tool wait needs a short
  deadline or an explicit deny-on-timeout; (b) `session/cancel` does not
  promptly interrupt an in-flight permission wait (product mitigates by
  rejecting the pending permission on cancel); (c) intermittent
  first-write-of-turn executing without a surfaced permission (F3 — needs
  attribution in the write/edit approver wiring); (d) bridge crash on
  cancel during a live tool call (`GenerationState.postToolCall` →
  `_dispatch_lane_barrier_sync` — the callback-after-delete class). Full
  rows: `benchmark/runs/delegation_phase1_5.md`.
  Product boundary: the agent-doc model, topology rules and the
  composition law are owned by the product — last_answer
  `docs/decisions/0003-agents-live-in-docs.md`, forward plan
  `last_answer/docs/PLAN.md` (its Phase 1.5 = the HUMAN gate: the AFM
  pipeline usable in the GUI with no terminal; the dylib bundling lands
  in the Runner build phase, loader changes in
  `xsoulspace_inference_apple_foundation` — product-agnostic), handoff
  brief `last_answer/docs/HANDOFF-agents-in-docs.md`, landed record
  `last_answer/docs/history.md`. **Phase 1 LANDED
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
