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

| Issue                                                                                                                | Where                                                  | Next move                                                                      |
| -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------ |
| ~~Double-spawn race in extension recovery (two spawns race → one client attaches to a dead socket)~~ | `r7_harnessd_extension.ts` | FIXED 2026-09-06: `ensureClient` serialized behind ONE shared in-flight promise (concurrent callers await the same spawn/attach); failed attach no longer caches the dead stdio shell |
| ~~Warm-tick floor ~1.4 s on the monorepo (full fs walk per tick for add/drop detection)~~ | `fs_etl.dart` | FIXED 2026-09-06: `reconcileFsTier` — stat stored file nodes, listSync only mtime-moved dirs; MEASURED 24 ms no-op tick (budget <300 ms PASS); gates `etl_tick_test.dart` + `tool/warm_tick_probe.dart` |
| ~~`harness_verify` unwired: the extension cannot pass a per-package `--check`; monorepo-root verify is meaningless~~ | `harnessd_cli.dart` (`--check` exists) + extension env | MOSTLY FIXED: `HARNESSD_CHECK` env → spawn args wired (ADR 0027 §4). REMAINING: the extension should derive the ACTIVE package's convention automatically (today it is env-declared by the caller) |
| `harness_fs_write` routes whole-file content through the MOVER as a graded task | `harness_acp_backend.dart` (remote mover) | FIXED 2026-09-06: `isMechanicalWriteDirective` + `_runMechanicalWrites` — a directive-only `harness_fs_write {…}` prompt now executes through the review gate (jail-resolve → consent round-trip → write → tree reconcile) with ZERO mover involvement; no approver wired → refusal (deny-by-default structural); mixed prompts never take the path. Gate: `harnessd_mechanical_write_test.dart` (allow lands + reconciles / reject never lands / no-approver refusal / mixed-prompt classification). REMAINING: consent wait needs a short deadline + deny-on-timeout (Phase 1.5 finding (a)) |
| ~~`packConsent` unwired on the DAEMON edit tool (P1 trusted-author follow-up)~~ | `coding_agent_runner.dart` + `harness_acp_backend.dart` | FIXED 2026-09-06 (lane A subagent): SYNC consent-plan answer (planAllows-style) threaded through runCodingAgentOnce; `pack_write` verb added to the consent-plan vocabulary + `.harnessd/consent.json`; every answer audited in consentLog; no plan → entry skips as named data, tool construction never crashes. Gate: `harnessd_pack_consent_test.dart` (main gate: plan-allowed authored entry realizes + applies, zero round-trips, audited; no-plan: skipped + bounce, refusal audited); host suite 43/43 |
| Root convention is a MONOREPO compromise (`flutter test` over root test/) — per-package tasks need per-package gates | `workspace_conventions.dart`                           | task sentences carry `--check` (the D8 convention stays the default)           |
| Zoom staleness: cut props can lag a just-refreshed tree (mtime-reconciled nodes)                                     | `meaning_query_tools.dart`                             | zoom re-stats the focus node (cheap)                                           |
| ~~Discovery unbundled: `locate` (ADR 0014 §2) never re-based onto the meaning tree; agents bootstrapped ids by grep~~ | `meaning_locate_tool.dart` + daemon + extension | FIXED 2026-09-06: `meaning_locate` — tree-native ray (ranked, class-agnostic, refs-counted, token-bounded) registered in the meaning profile, the daemon read world, the scripted actor and the pi extension (`harness_locate`); gate `meaning_locate_tool_test.dart` (5 tests) |

### Untested surface (built, never proven end-to-end)

| Feature                                                                   | Gate that must run                                                | Status                           |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------- |
| Consent plans (bounded grants, audit)                                     | host unit tests green; NO real pi session has granted/audited one | unit-only                        |
| Reasoning beats (`thinking` capture, escalation reuse, `reasoning` hints) | scripted tests green; NO real-model run has exercised them        | unit-only                        |
| `remove_member` (retire) on a REAL model flow                             | scripted gates green; no AFM/OpenRouter retirement attempt        | unit-only                        |
| `harnessd --check` override                                               | implemented this session, zero runs                               | untested                         |
| File-class registry extension path (register md/yaml/json `parse` fns)    | registry unit-tested via tick; no non-dart class registered yet   | path-only                        |
| Pack work-orders (multi-edit consent-once work orders)                    | —                                                                 | designed (ledger row), not built |
| Multi-workspace daemon (last_answer co-tenancy)                           | —                                                                 | P4, not built                    |
| Refactor executables (`rename_package` packs)                             | —                                                                 | designed (ledger row), not built |

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

## NOW — the pi-dogfooding path (prioritized, transparent)

The production path (#1–#7) is COMPLETE — every gate has a published row
([history.md](history.md), [results_r7.md](results_r7.md)). The next
race is **turning the harness into pi's own work surface** — and into a
surface where ANY model needs no raw tools (grep/read/bash have no role).
Priorities below are ordered by the dogfood evidence: every row exists
because a real session hit the wall, and every row names its gate and its
status. Nothing here is aspirational prose.

### Priority ledger (2026-09-06)

| P | Item | Status | Gate |
|---|---|---|---|
| P0 | Mechanical directive tier: reads (`[scan]`/zoom/impact/locate) + consented writes (`harness_fs_write` through the review gate, consent-plan inherited) | **DONE 2026-09-06** — measured: reads 12–144 ms; writes bounce no more (`mover_refusal` class dead) | `reads_are_not_builds_test.dart`, `harnessd_mechanical_write_test.dart` |
| P0 | Discovery ray on the tree: `meaning_locate` (ranked, class-agnostic, refs-counted) on meaning profile + daemon + extension | **DONE 2026-09-06** | `meaning_locate_tool_test.dart` |
| P0 | Warm tick < 300 ms (tree-driven reconcile) | **DONE 2026-09-06** — 24 ms on 2,450 files | `etl_tick_test.dart`, `tool/warm_tick_probe.dart` |
| P0 | Capability ops (effects-as-data): hosts register jailed I/O ops AS DATA; intents compose real capabilities | **LANDED 2026-09-06** (`fs_stat` first) — interpreter tier; materialization of effect ops = named bounce until each op's emitter lands | effects tests (harness + workspace) |
| P1 | `harness_run` on the pi surface (allowlisted commands, per-file test/analyze scopes) | **LANDED 2026-09-06** — mechanical directive, server-side allowlist | `harnessd_mechanical_run_test.dart` |
| P1 | Consent plans shipped for this repo (`.harnessd/consent.json`) | **DONE 2026-09-06** | `consent_workspace_file_test.dart` |
| P1 | Trusted-author tier: authored-body pack executable (consent-at-pack-write, same three fences + oracle + auto-revert) — completes harness self-hosting | **LANDED 2026-09-06** — `EditExecutableKind.authoredBody` (AE wire) + span-editor realization (consent gate deny-by-default, unified-diff rendering, coverage fence + oracles + auto-revert unchanged) + pack round-trip; EXPRESSION-BODIED (`=>`) members now realizable (pre-existing cursor bug found by the dogfood); **self-hosting row GREEN** (`benchmark/runs/trusted_author_row.md`): real fix `dart/quote_aware_check_split` landed at zero authored tokens, analyze 167 ms, full suite 34 s, 413/0 | `span_edit_gate_test.dart` (+4 trusted-author tests), `benchmark/runs/trusted_author_row.md` |
| P1 | Docs oracle for md (structural nodes first, fill gaps in-between) — **md LANDED 2026-09-06** (lane B subagent): `md_materializer.dart` + `edit_section` verb (anchor-resolved section splice, byte-precise, 0-broken-links oracle with auto-revert, named failure classes, spec registered AS DATA in `file_class_spec.dart`, tick maps md); gate `md_materializer_test.dart` 8/8, workspace suite 56/56. NAMED DEFERRED: REAL-model R7e tiny-model gate row (needs on-device AFM run). Remaining: yaml/json materializers (keypath splice, comment-preserving; parse + semantic-diff oracle) — the `MaterializerSpec` registry shape is ready | md gate + tiny-model row |
| P2 | Pack inventory as MEANING nodes (`kind: 'executable'`, impl edges) — the agent zooms its own capabilities; task-grammar classifier → one-decision e2e for the structured 80% | designed (decision-amortization discussion), not built | capture-loop e2e + pass@1 row |
| P2 | Topology engine: task-declared `{worlds, actors, roles, model-tiers, budgets}` as data; **meaning-part actors** (mechanical systems are zero-token actors with scripted handlers — same loop, same beats, same budgets) | P4, expanded 2026-09-06 | topology selection e2e |
| P2 | Execution as meaning: `run` declarations as intent nodes, run OUTCOMES as beats (append-only — the tree stays re-derivable), stdout/stderr as budgeted span anchors; speculative verify actor after git-as-meaning | **DESIGN below**, not built | run-meaning e2e |
| P3 | VCS as meaning projection (versions/branches as nodes; git replaceable) | direction, not built | refs-frontier oracle |
| P3 | AE knowledge plane: harness trees ⇄ AE canonical packs; **ROUND-TRIP GATE GREEN 2026-09-06** (lane C subagent, `agentic_executables_wire`): `ae.knowledge_pack.v1` envelope — kinds intent (impl/then op-chains), op, step (DependsOnStep + GoalLink), goal, section, spec, feature; construct/deconstruct deterministic (byte-identical canonical form), unknown kinds fail LOUDLY, corrupted rows skip as named data; gate `meaning_tree_round_trip_test.dart` 13 tests (26/26 suite). NAMED, NOT BUILT: `ae know` CLI over `.ae_ln/` canonicals; hub distribution/versioning; harness-side host adapter (export → MeaningNode world state) | round-trip ETL gate |

### Directions (discussed 2026-09-06 — the design behind the ledger)

1. **Decision amortization.** One prompt → one decision → verdict, for
   the structured 80%: authored tokens per task → 0 (R7d proved the
   endpoint: pack-fed edit, pass@3, zero authored tokens). The capture
   loop is a compiler of experience; bounces are future pack entries;
   the pack inventory becomes zoomable meaning. Working with code is
   highly structural — most task sentences parse to
   `{verb-class, target, params}` → repair-class lookup →
   `apply_executable` → oracle.
2. **Execution as meaning (critical design).** A process is a meaning:
   `run` DECLARATIONS are intent nodes (re-derivable); run OUTCOMES are
   BEATS (append-only, never projected as re-derivable state — a process
   outcome is not re-derivable, so it must not lie in the tree);
   stdout/stderr are span anchors read budgeted (like md sections);
   exit/duration are props. Composability: pipelines = intent chains
   calling run intents; speculative worlds branch at run nodes.
   Safety: the allowlist law stands; capability grants are per-actor
   data; output never enters context except as a span cut. Beats and
   projections apply to executions exactly as the user framed it —
   execution context is just another dimension of the map-graph.
3. **AE knowledge plane.** AE canonical packs are the meaning tree AT
   REST (verified, hub-distributed); the harness tree is the same
   meaning IN MOTION. Construct/deconstruct = distill (sources →
   canonical rows) and export (canonical → tree nodes) — both exist in
   `meaning_tree_export.dart`; what's missing is wiring harness intent/
   plan/spec populations through it so knowledge is packaged, versioned
   and shared via the local/remote hubs instead of living only in
   session state. We own both projects — the seam is ours to cut.
4. **MMO frame.** Many small fast decisions; several actors may share
   one model; mechanical systems are zero-token actors. Latency of truth
   leaves the critical path via speculative verification (verifier as a
   concurrent actor; roll back at run-node boundaries).

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
      drive a _running_ Flutter app (semantic snapshots, tap, hot-reload)
      through one MCP tool surface; the harness sees the same `intent_call`
      shape over a transport adapter (D5). Unblocks after the edit-tier loop
      proves on-device.
