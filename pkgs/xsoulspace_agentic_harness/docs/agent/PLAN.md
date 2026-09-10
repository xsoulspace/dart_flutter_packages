# Agent Harness — Plan (forward ledger)

> FORWARD RECORD ONLY. Everything landed lives in [history.md](history.md)
> (A–I, J/K, M, N, P, R6, R7, the 2026-09-06 pi-dogfooding surface wave, the
> closed race tracks R1–R8, and the proven-claims ledger); durable decisions
> in the [ADR Index](../../../../docs/decisions/README.md); benchmark rows in
> `results_*.md` (current: [results_r7.md](results_r7.md)) and
> `benchmark/runs/*`. The coding pipeline end-to-end:
> [pipeline_coding.md](pipeline_coding.md).
>
> House rule for this plan: **the coding agent IS the coding agent.** Issues
> in its own packages are its backlog, delegated to its own actors. pi
> orchestrates and escalates; pi does not absorb fixes the harness can do.

## Open issues (honest ledger, 2026-09-06)

| Issue | Where | Next move |
| --- | --- | --- |
| **URGENT — `harness_verify` over budget (MEASURED 156.9 s vs the 90 s dart-turn budget, 2026-09-06)**: resolve VIA DOGFOODING — the verify directive derives the ACTIVE package(s) from the touched-file beats (the `VerifyTierPlanner` derivation already knows them) and runs THAT package's convention in ITS directory (narrow `dart test <files>` shape; root convention only as fallback); the verify wall is REPORTED in the verdict data so misses are visible | `harnessd_cli.dart` + `verify_tiers.dart` + `workspace_conventions.dart` | verify-after-touch runs the touched package's convention, wall < 90 s; fallback proven; harness_verify re-metered on this repo |
| ~~Bridge crash on cancel during a live tool call~~ **one variant FIXED 2026-09-07** (ADR 0033 §4 made it reachable): `postToolCall` resumed the tool continuation with a cancellation error AND `NativeDartTool.call` resumed it again (`NativeToolError`) — a FATAL double resume, gated by the bridge unit suite; the end-after-move path now sets `finished` under the lock and delivers the done payload manually (lock order preserved). The wider callback-after-delete class stays open pending the on-device re-run | `bridge/src/bridge.swift` | on-device wave rows run clean end-to-end |
| Root convention is a MONOREPO compromise (`flutter test` over root test/) | `workspace_conventions.dart` | per-package tasks carry `--check`; the D8 convention stays the default |
| New-task goal isolation on a resumed world | per-workspace snapshot store | the store carried the previous goal; the small model replayed it (Phase 1 dogfood) |
| Bridge crash on cancel during a live tool call | `GenerationState.postToolCall` → `_dispatch_lane_barrier_sync` | callback-after-delete class (Phase 1.5 finding (d)) |

### Untested surface (built, never proven end-to-end)

| Feature | Gate that must run | Status |
| --- | --- | --- |
| REAL-model gates for the new tiers (R7e tiny-model, on-device AFM) | trusted-author `apply_executable`, **the UNIFIED edit verb (md sections + yaml keys, ADR 0034)**, task-grammar pre-pass — each needs one real-model row | named deferred — needs the on-device AFM run (NOW P0) |
| Consent plans granted/audited in a REAL pi session | a real session grants one, audits consentLog | unit-only |
| Reasoning beats (`thinking` capture, escalation reuse) | a real-model run exercises them | unit-only |
| `remove_member` (retire) on a REAL model flow | an AFM/OpenRouter retirement attempt | unit-only |
| Pack work-orders (multi-edit consent-once work orders) | — | designed, not built |
| Refactor executables (`rename_package` packs) | — | designed, not built |
| Multi-workspace daemon (last_answer co-tenancy) | — | P4, not built |

### How to work via harness for ALL files (the route, post-2026-09-06)

1. **Dart**: `harness_scan` → `harness_locate` → `harness_zoom`/`harness_impact` → `harness_edit` (replace/insert/remove/apply_executable) → `harness_verify`. Fences: coverage, expressiveness, integration, refs.
2. **md / yaml / json (ADR 0034 — ONE edit verb)**: `harness_edit` carries the class-routed action union — sections (`replace_section | insert_section | append_to_section`, heading-bearing body), keys (`set_key | replace_value | delete_key | append_list_item`), creation via `anchor` (the class's declared anchor currency). The model surface has NO edit_section/edit_key verbs; the workspace package keeps the per-format ToolDefs for LLM-free materializer tests only.
4. **trusted-author fixes**: a consented `authored_body` pack entry applies via `apply_executable` at zero authored tokens (consent plans: `pack_write` verb; permission waits resolve deny at 45 s — `permission_timeout` — and cancel denies promptly; every decision audited with its path).
5. **everything else** (`other`): visible in the tree, review-gated `write_review` only — by design, never by omission.
6. **The extension of the surface itself** = register a file-class binding (ADR 0035: the tiny `MaterializerBinding` record — fileClass, extensions, actions, materializer, mapBuilder, subNodePrefix) in `xsoulspace_agentic_workspace` — the same closed verb surface, more covered reality. Tiered landing (ADR 0035 §6): mapless → review-gate only; fs-tier → sub-nodes + class actions; code-tier → symbol map + analyzer oracle + convention (dart today; ts/c# staged — v1 pack-fed bodies, v2 op-chain back-ends evidence-gated). Lint-class repairs are OUT of scope by disposition (per-project; `dart fix` / custom lint CLIs own them).

## NOW — the remaining frontier (prioritized)

**2026-09-08 (latest) — the ACTOR-CONTRACT WAVE (8 lanes, landed + integrated):**
the build order from the pi-as-actor analysis landed as eight parallel lanes
(spawned pi agents with strict file-ownership discipline — rung-1 workers
building their own rungs; 6 lanes died once on API timeouts and were
completed as continuations that inventoried + finished the partial work):

| # | Item | Landed as | Gate |
|---|---|---|---|
| 1 | Session-actor tier contract | `session_tier.dart` (host): `SessionTierProfile` + `resolveSessionTier` deriving from the ADR 0033 equation; ladder `perOp = clamp(window/32, 512, 4096)`, `verdict = max(1200, perOp×2)`; AFM 4096 → 512/1200 (bit-identical to the read program's defaults); 128k/200k → 4096/8192; config keys `session_tier_per_op_read_budget(_<backend>)`; the extension declares the tier at `session/new` (`_meta.sessionTier`) and sources per-op budgets from it (`.pi/extensions` copy is now a symlink to the pi_driver copy) | `host/test/session_tier_test.dart` 4/4 (AFM 628-row reproduces from tier terms; cross-truth row pins the AFM budgets == the harness constants) |
| 2 | Mechanical `harness_edit` directive path (P0) | `mechanical_edit_directive.dart` (host): pure-JSON classifier (deny-by-default, mixed prose never mechanical) + payload validation; backend routes it BEFORE the graded path (consent via the existing UX machinery; touched-file beat lands on the goal actor's thread); `_runMoverRefusalEditFallback` executes a single well-formed payload mechanically after a mover refusal — the measured 103–183 s `mover_refusal` class is dead | `host/test/harnessd_mechanical_edit_test.dart` 6/6 + mechanical_write 4/4 no-regression |
| 3 | The deferred-task law | `deferred_task_policy.dart` (harness): `kDeferredClasses` table AS DATA (test-run, pub-get, build, app-run, dylib-build), interactive intents NEVER defer; `DeferredVerifyPool` keyed per (package, convention) — a second requester JOINS, one task, N completion beats; accounting + named defects for a deferral that never produced its verification beat; OPT-IN (`wireDeferredVerify`), disabled by default | `harness/test/deferred_task_policy_test.dart` 8/8 + `host/test/deferred_verify_pool_test.dart` 3/3 (join proven: one task, two beats, `verify_wall_ms` as beat data) |
| 4 | Actor-scoped consent plans | `tooling/consent_scoping.dart` (harness): ConsentPlan v2 `{planId, actor, scopePathGlob, verbs, maxUses, ttl, grantedAt}`, PURE deny-by-default evaluator with named reasons, actor-keyed append-only audit, v1 backward-compatible parse, named errors; NOT wired (pure model — integration hooks documented in `docs/agent/consent_scoping.md`) | `harness/test/consent_scoping_test.dart` 18/18 |
| 5 | Workers as extension clients (rung 1) | `docs/agent/multi_actor_workers.md` (the rung-1 contract; rung 1 honestly a TRANSITIONAL wedge; replacement metric = harness-decision share + escape rate → 0) + `worker_spawn_brief_template.md` + `run_r7_multi_worker_gate.mjs` — the SCRIPTED gate PROVED rung 1 end-to-end: two ACP clients on one daemon, same session, both edits landed, suite green, second daemon refused | driver `--scripted` PASS (~22 s; transcript `benchmark/runs/r7_multi_worker_transcript.txt`) |
| 6 | Topology as data + step claiming (rung 2) | `decisions/actor_topology.dart`: `ActorTopologySpec` (`{worlds, actors:[{id, role, tier, budget, toolRegistry}]}`) registered as graph data (`TopologyActor` + `StepClaimant` components, APPEND-ONLY per the ecsly invariant); `claimStep`/`claimStepStrict` — second claim bounces `step_already_claimed` carrying the claimant; frontier rows project `claim`/`claimedBy`/`claimable`; `workClaimedReadyStep` reuses mechanical_actor's deny-by-default. NO coordinator (ADR 0009 clause holds); release/steal NOT built | `harness/test/actor_topology_test.dart` + `step_claim_test.dart` 11/11 (every world test `expectIdle`) + projection/regression suites 79 pass |
| 7 | Binding-typed file creation | ADR 0035 bindings gain `fileCreation` capability data (`create_document`; md `new_file_path`, yaml/json `new_file_path#keypath`); routed through the ONE edit verb with named bounces (no-creation binding, never-overwrite, stale-dir); oracle-gated with revert-to-absence; tree re-derives (file node + sub-nodes). Dart deliberately NOT covered (code creation = trusted-author tier) | `workspace/test/file_creation_binding_test.dart` 21/21 + existing materializer gates 33/33 |
| 8 | Structural executables | `EditExecutableKind.addConstructorParam`/`addEnumCase` (wire repo, +2 round-trip tests) realized in `span_editor.dart`: host splices constructor signature + backing field + initializer / enum case byte-precisely (adjacent-line punctuation repair family); `_requireStructuralConsent` — deny-by-default at apply time; coverage fence deliberately NOT applied (shape-adding, not behavior-replacing) | `workspace/test/structural_pack_test.dart` 5/5 + span/pack gates 14/14; wire repo 35 tests, analyze clean |

**Integration pass (this session, after the lanes):** the structural kinds
grew `edit_symbol`'s metered surface (705 → 1,029; total 1,695 →
cutBudget 381, fits=FALSE) — repaired per ADR 0030 convergence (the 9
redundant flat `executableParams` props dropped — the pack's named bounce
teaches the spec — and the description compacted): edit_symbol 786, total
**1,452, inside the published range, fits=true**; the overhead gate is the
trace that polices every surface change. Pre-existing
`zoom_staleness_probe.dart` analyzer error fixed (dynamic-call cast).
Full suites after integration: **workspace 130/0, harness 446/0, host
89/0**; analyze 0 errors in all three; wire repo 35/0.

**Named follow-ups — EXECUTED 2026-09-09 (the 3-lane follow-up wave, verified):**
(1) server-side tier enforcement — LANDED: `AcpSessionNewRequest` carries
`_meta` through `dart_acp_toolkit` (17/17 wire tests), the backend parses
`_meta.sessionTier` (`parseSessionTierMeta`, named errors) and threads the
tier's budgets into `meaningProgramTool` (opt-in params, zero change when
absent); gate `session_tier_server_test.dart` 4/4 — a budget-less `read`
serves WHOLE under a hosted tier vs CLIPPED at the 512 default.
(2) Production deferral wiring — LANDED, ON for the harnessd daemon path
(`--no-defer-verify` restores inline; library default OFF): the verify
call-site wraps the planner in `DeferredVerifyPlanner` (join per
(package, convention), executor-once), the executor spawns the package's
convention (120 s ceiling), and the final gate stays the INLINE terminal
proof; measured row in `results_seam_speed.md` (grade decision 11 ms,
verify wall 24 ms as beat data, join 2→1 task/2 beats; fixture-metered,
n=1, scripted). (3) Consent-scoping integration — LANDED: the daemon's
consent paths route through `ConsentLedger.matches` with the
`harnessd@<workspace-path>` actor id; actor-keyed append-only audit with
structured `consent-row` lines; v1 workspace consent unchanged; v2 loads
via `setSessionConsentDocument` (auto-load at session creation still
open). (4) Mechanical-actor consent ← the ledger — LANDED
(`consentFromLedger`; proven at the harness gate; no host call-site yet).
Verification: host 104/104, harness 454/454 (one long-horizon timing
flake passed on re-run — parallel-suite latency gate), analyze 0 errors
across workspace/harness/host + the acp_toolkit wire repo (17/17 tests,
0 errors). `consent_scoping.md` § Non-claims updated (wired status).

**2026-09-07 state (the derived-context wave, ADR 0033/0034):** the meaning
profile GRADUATED — the read program replaced locate/zoom/impact (daemon
read world converged too), the ONE edit verb absorbed edit_section/edit_key
(class-routed union + parent-addressed creation), the derived context
equation replaced the four constants (configurable per backend via
`derived_context_*` keys), repair is mechanical (window-class failures DROP
the decision, never a same-cut retry), and the decision ends MECHANICALLY
after the move (`end_after_tool`). **Sequencing agreement (2026-09-07):**
the P1 ToolCallError fix + P0 rows 2–4 re-run run FIRST (the union-enum
graduation measurement); the ADR 0035 binding-registry work proceeds as a
separate suite-green commit series in parallel — never mixed with the wave
run or the deferred `edit_node` rename. Measured row: **1,424 chars/4 →
cutBudget 628, fits=true** — the 4k AFM tier funds a cut for the first time
(pre-graduation: 2,268 → 36). The first on-device smoke PROVED the flag
(generations end on the first tool result) and found+fixed a FATAL
double-resume in the bridge. What remains, ordered:

| P | Item | Status | Gate |
|---|---|---|---|
| P0 | **THE ON-DEVICE WAVE RE-RUN** — EXECUTED 2026-09-07 (see `afm_wave_results.md` § P0 RE-RUN). Row 1 PASS 1/1 at HALF the 2026-09-06 tokens (2,024/1 decision/24.5 s) — `end_after_tool` proven on-device. Rows 2–4 died in ONE NEW SYSTEMIC CLASS: **opaque schema-invalid tool calls** (`ToolCallError` → bare `generation_error` → same-cut retry — the call never reaches Dart, so the ADR 0034 named-bounce contract cannot fire; 18/8/10 ToolCallErrors per row, loops of 59–109 generations, uncontained by maxToolRounds) | **P1 landed + the re-run EXECUTED 2026-09-08** (`afm_wave_results.md` § P1-FIX RE-RUN): the ToolCallError class is GONE (verdicts publish, classes named); row 1 PASS 1/1 reproducibly; rows 2–4 FAIL in named classes (read-side query/id composition; early-stop) — the MEASURED no-recovery verdict for the 4k multi-step flow; named repairs recorded (host pre-pass for mechanically-resolvable rows — measured, not assumed; tier escalation J8.2) |
| P1 | **Opaque ToolCallError class (the P0 finding)**: the bridge catches `ToolCallError` → NAMED `tool_args_invalid` (tool + framework detail); the harness records it as bounce-class data (a named beat: required slots per class) — never a same-cut retry; maxToolRounds must count failed generations too | **UNIT-GATED 2026-09-07** (bridge classification on BOTH generate paths + harness named bounce beat + failed-generation round counting; gate: `test/tool_args_invalid_bounce_test.dart` 3/3 + `check_bridge_swift.sh` unit 27/27) | rows 2–4 re-run: the bounce loop teaches recovery (or the enum splits per class — measured) |
| P1 | **Native-truth pre-flight**: the 1.45 factor is a measured APPROXIMATION on JSON-heavy content. The durable fix is named in the client already (`model.tokenCount(for:)`) — expose it over the bridge (`xs_fm_token_count`) and pre-flight with native truth; the equation keeps its shape, the factor term goes to 1.0 (config default stays until measured) | named (R9.1), not built | derivation row vs native baselineTranscriptTokens agreement ±5% over 10 runs |
| P2 | **`surface_capability_diff` gate**: when a verb is ABSORBED, mechanically diff the absorbed verbs' arg space against the survivor — the creation regression (the unified verb could not CREATE keys) would have been named at unification time, not by hand (surface_gaps 2026-09-07) | gap logged, not built | the gate runs on every surface change; any lost capability is a named row |
| P2 | **Wave instrument: split the failure classes.** The 2026-09-06 rows conflated overflow loops with model scan-loops; the summary must classify `decision_dropped` (window) vs repeated-identical-moves (task framing) vs final-gate misses — an instrument that cannot distinguish them misattributes the next run | not built | summary rows carry the class; n>1 per row |
| P2 | Speculative verify actor; topology engine; registry linter (unchanged from 2026-09-06 — designed, not built) | designed | per-row gates below |
| P3 | **`edit_node` rename** (ADR 0034 disposition 2): string-mechanical, 87 refs, token-neutral — lands in the SAME batch as any fix the P0 run forces, never mid-flight (conflict hazard with parallel unification work) | deferred, trigger = P0 landed | rename lands; gates re-run green; no re-measurement needed |
| P3 | **Mutation ops joining `meaning_program`** (ADR 0034 disposition 3): trigger = a P0/P1 row where read/edit alternation dominates tokens/decision. NOT a wiring task — the three design constraints are recorded in ADR 0034 (transactional all-or-nothing; consent scoping; the program IS the move) | deferred, design recorded | the trigger row + the three constraints implemented together |
| P3 | AE knowledge plane completion; multi-workspace daemon (unchanged) | named | per-row gates below |
| ✅ DONE 2026-09-08 | ~~ADR 0035 binding registry + fs-tier map ownership + span_editor safe decomposition~~ (the `switch (node.kind)` dead; `_mapClasses`/`_mapPrefixes` dead; `dart_lexicon`+`edit_pack` extracted; suite 86/0) | **LANDED** — four MoE-reviewed lanes | [history.md](history.md) § 2026-09-08 |
| ✅ DONE 2026-09-08 | ~~Language families: TS and C# (ADR 0035 §6)~~ — **BOTH LANDED**: ts (tsym_ scanner, tsc_no_emit oracle, delta 0 on all 4 fixtures) + cs (csym_ scanner incl. block namespaces + unicode-regex fix, dotnet_build oracle, delta 0 on 2 fixtures; csproj = Tier A disposition, xml binding named-not-built). Suite 104/0. `replace_member_body` omitted on both — the limitation teaches via the class-scoped bounce | **LANDED** | [results_etl_grammar.md](../benchmark/runs/results_etl_grammar.md) delta tables; per-language matrix below — the R7e on-device rows remain the open gate |
| P2 | **tree-sitter ETL-in (named, evidence-gated — ADR 0035 §7)**: no FFI dep until (1) ≥3 named mechanical-scanner failure classes, (2) a measured workaround-cost row, (3) a spike proving grammar→meaning nodes with zero host-authored expectations, (4) budget proof the 4k tier still fits | gate recorded in ADR 0035; not built | all four clauses met; otherwise the gate stays |
| P2 | **tree-sitter spike (ADR 0035 §8 — separability scope, one grammar)**: `xsoulspace_treesitter_raw` (the ONLY dart:ffi import, LEAF pkg, zero workspace imports) + `SourceParser`/`ParserConformance` seam + span bridge (UTF-8→UTF-16→source_span, multibyte golden tests) + generic query+map interpreter + TS mapping table (member symbols day one) + conformance battery run against BOTH the mechanical TS scanner and the FFI impl — the conformance DELTA is the clause-1 evidence, measured as data | scoped (ADR 0035 §8), not built | results row `results_etl_grammar.md`: clauses 3–4 pre-seeded (zero-host-authored mapping + budget proof); clauses 1–2 stay open pending REAL task rows — no FFI dep in the workspace regardless |
| P2 | Speculative verify actor: run-node world-fork primitive (beat watermark), outcome-beat arbitration (canonical wins, `speculative: true` flag), shared `RunMeaningExecutor` reusing `runTool`'s allowlist verbatim | designed (lane F report, 2026-09-06), not built | speculative-vs-canonical disagree → rollback e2e |
| P2 | Topology engine: task-declared `{worlds, actors, roles, model-tiers, budgets}` as data; meaning-part actors (zero-token, scripted handlers — same loop, beats, budgets) | designed, not built | topology selection e2e |
| P2 | Surface ergonomics (P0.5): registration-time linter over `ToolDef`s enforcing the R7e rules (required anchor slots on the wire, mechanical label resolution, bounces carry repairs) | not started | registry-lint gate |
| P3 | AE knowledge plane completion: harness-side host adapter (export → `MeaningNode` world state); remote hub fetch/push + trust/signing model; `ae know` subcommand family per the AE repo's `docs/ae_know_design.md` | CLI + local hub landed; adapter/remote named | hub round-trip against a LIVE harness world |
| P3 | Multi-workspace daemon (last_answer co-tenancy) | not built | co-tenancy e2e |

| P1 | **The exhausted-attempt pump (J8.1, the named driver defect from the 2026-09-08 re-run)**: after the goal-attempt budget exhausts, the react-continuation pump re-sent the identical "attempt N/3" prompt (measured Σ26, ~2 min wall, ~10k tokens) instead of ending the decision | **LANDED 2026-09-08** — the pump's fuel was the STALE failed `GoalVerified` re-firing the repair policy on every tool-result marker: `RunGradedGoalPolicy` now CONSUMES the verdict (one failed verification re-prompts EXACTLY ONCE; the next verifier stamp gates the next re-send); `ReActContinuationPolicy` gains the J8.1 exhaustion gate (a continuation never outlives the budget); the driver's repair loop BREAKS on `GoalAttemptsExhausted` and READS the monotonic `AttemptCount` (never clobbers — one budget truth). Gates: `exactly_one_resend_test.dart` 4/4 + `harnessd_pump_gate_test.dart` (scripted, LLM-free: no duplicate repair prompt, attempt numbers strictly advance, the failing run ends on exhaustion) + the J1.5 F1 suite re-pointed to the fixed law | the on-device re-run rows publish without pump burns (decisions bounded, no identical re-opens) |
| P1 | **Resolvers INTO the plan frontier (repair (a), DECIDED + owner-corrected — NO new mechanism)**: `StepAction` steps get mechanical resolution (pack/grammar/prompt-named anchors) and the ready decision delivers via the EXISTING decision flow (`openFreshDecision`); zero-token mechanical actors work consented ready steps while the model actor works (the ADR 0009 accelerate-and-predict frontier, unified with the task-grammar pre-pass fork). Prerequisite: the exhausted-attempt pump fix | **LANDED 2026-09-08** — `step_resolver.dart` (the ONE resolver: grammar verbs → prompt-named anchors (md sections / yaml keypaths / backticked symbol+executable — the wave rows 2–4 class) → total-or-bounce with REAL candidate ids); the task-grammar pre-pass RETIRED into it (one mechanism); `spawnResolvedStep` lands the resolved step as graph data (StepAction.outcome carries the classification); `mechanical_actor.dart` executes CONSENTED ready steps (deny-by-default). **On-device: row 1 (grammar path) PASS 1/1 at 2 decisions THROUGH the resolver**; the `--dry` pre-flight resolves ALL FOUR row prompts Ready with exact ids over the real jail trees; the class split holds (composition_required ≈ 0). **Named residual (the md row, 3 attempts, machine-time law)**: the 4k model does not carry a ready move over a long task text with contradictory flow teaching (directive led AND superseded — still explored); next repair named in `afm_wave_results.md` § FRONTIER-RESOLVER RUNS (goal-frame carries directive + body DATA only, flow teaching stripped) | wave rows 2–4 on-device after the goal-frame composition repair (rows re-run pass@1, 1–2 decisions) |
| P2 | **Tier routing as a FRONTIER PROPERTY (repair (b), DECIDED)**: a step the resolver cannot resolve projects as tier-routed (topology-engine model-tiers-per-role); up-front routing, J8.2 overseer stays fallback. Build trigger: the first unresolvable-frontier task (three-failures rule) | **The (b) CLASSIFICATION landed as DATA 2026-09-08** (`TierRoutedStep` — a sentence no mechanical pattern covers projects tier-routed; `step_resolver_test.dart` pins it). The routing MACHINERY stays named-not-built (0% of failed steps needed composition — the trigger is unmet) | the trigger task row + the routing beat logged with its class |
| P2 | **Wave-log classifier as a repeatable analyzer**: classify each burned step (mechanically-resolvable vs composition-required) from run logs — the decision instrument for (a)/(b) boundaries | **LANDED 2026-09-08** — `benchmark/wave_log_classifier.dart` (the (a)/(b) boundary is a const DATA TABLE, `kWaveLogClasses`; 11 named classes + `unparseable` publishes as data); wired into the wave driver summary (`log_class_split` per run, `class_split` per row). Reproduced mechanically on the real logs: **composition_required = 0** (the DECIDED 0%-composition measurement). Gate: `wave_log_classifier_test.dart` 5/5 incl. a real-log fixture | the analyzer runs on every wave re-run; summary rows carry the class split |
| P3 | **XML binding (Tier B, ADR 0035 §6)**: keypath currency over tags (xpath-like), xml parse + semantic-diff oracle — the keypath materializer generalized; serves `*.csproj` (+ any xml config). Named-not-built by the cs-family disposition (a hand-rolled parser breaches the no-new-dep bar). Build trigger: a real task editing csproj/xml config through the verb (three-failures rule), or the first dogfooding wave that needs it | named (cs landing, 2026-09-08), not built | xml binding + registry linter clean + one LLM-free csproj edit through the ONE verb; the cs matrix Tier B cell flips to ✅ |
| P2 | **The pi extension read dialect (the 2026-09-08 dogfood-debt rows, EXECUTED)**: the extension exposed the legacy per-verb read wrappers (every session read delegated to the mover: ~140 s + `mover_refusal`); the mechanical-read set was a name list, not a registry contract | **LANDED 2026-09-08** — the extension exposes ONE read tool (`harness_meaning_program {ops:[…]}`; `harness_locate`/`harness_zoom`/`harness_impact` REMOVED from the tool surface); the mechanical-read set is asserted against the LIVE one-truth registry BOTH ways (every recognized read form is served by the registry; the program op set derives from the LIVE tool's closed-set halt bounce; the legacy wrapper names are pinned out) — `mechanical_read_registry_test.dart`; the read wall over the REAL monorepo tree measured **28 ms** (scripted probe `run_dogfood_seam_ab.mjs`); one REAL `harness_edit` md insert (the A/B row) landed THROUGH the md binding — A/B row in `results_seam_speed.md` | reads mechanical (<100 ms) on every future session; the registry test fails the drift class if it ever returns |

## Per-language gate matrix (ADR 0035 §6 — one row per family, all through the ONE edit verb)

| gate | dart | ts | c# |
|---|---|---|---|
| **Tier B — config edit through the verb** | (n/a — dart is code) `pubspec.yaml` via the yaml binding: `edit_node_unified_test` ✅ | `tsconfig.json`/`package.json` via the json binding: LLM-free jail test ✅ | `*.csproj` = **Tier A now** (review-gate writes); xml binding = PLAN P3 row |
| **Tier C — scanner map** | `scanDartFile` + symbol/member nodes (`etl_scale_tier*`) ✅ | `ts_materializer.dart` mapParser ✅ (delta 0) | `cs_materializer.dart` mapParser ✅ (delta 0; block namespaces, attribute riding) |
| **Tier C — edit half** | `span_edit_gate` + `pack_edit_gate` ✅ | insert/remove/apply_executable byte-precise ✅; limitation bounce ✅ | same shape ✅ (`cs_materializer_test` 9/9) |
| **Named oracle** | `dart analyze` + convention (scoped) ✅ | `tsc --noEmit` + oracle_unavailable pre-bytes ✅ (+cs_error-class auto-revert proof) | `dotnet build` + oracle_unavailable pre-bytes ✅ (fake-dotnet auto-revert proof) |
| **Conformance delta vs tree-sitter** | (n/a — dart has the analyzer) | **delta 0** on all 4 fixtures ✅ | **delta 0** on 2 fixtures ✅ (tree-sitter grammar pending — scanner-baseline table) |
| **R7e tiny-model gate (on-device)** | wave row `task_grammar` **PASS 1/1** ✅ | wave row `ts` — OPEN (builds after the frontier-resolver repair lands) | wave row `cs` — OPEN (same) |
| **Registry honesty** | binding linter green | + extension disjointness vs dart/json | + xml binding disjointness |

Landing order: ts (in flight) → c#. A language family is LANDED only when
every gate in its column is green; the R7e row is the on-device pass@1.

## Directions (the design behind the ledger — remaining frontier)

1. **Decision amortization** (LANDED for the structured path — task-grammar
   pre-pass + pack inventory, pass@1 1/1 at 1 move decision). Remaining:
   widen the grammar (verb coverage is mechanical four), usage-refs edges on
   executable nodes, and the daemon-row gate variant; prose stays excluded
   by design. The 2026-09-07 wave added the OTHER half of the law: the
   surface is derived (ADR 0033) and converged (ADR 0034) — one read
   program, one edit verb, creation included — so amortization is measured
   against a surface that no longer grows per format.
2. **Speculative verification** (the MMO frame): many small fast decisions;
   latency of truth leaves the critical path — the verifier is a concurrent
   actor, worlds branch at run-node boundaries, rollback = beat-truncation
   (outcomes are beats, never tree state). Needs the three seams named in
   the NOW P2 row.
3. **Knowledge at rest / in motion**: AE canonical packs are the meaning
   tree AT REST; the harness tree is the same meaning IN MOTION. Landed:
   the wire round-trip + local CLI. Remaining: wire LIVE harness populations
   (intent_define chains, plan beats, materializer specs) through the host
   adapter, then hub distribution with a trust model.

## Standing rules

- Every published number states backend, decision path, tokens source, tool surface, and n. Failures are data (classified, never dropped).
- Escalation-rate breakdown ships beside every pass-rate table.
- Gravity: tiny model stays useful; fewer LLM calls; context bounded+derived (D7: harness-owned); LLM-free testable. `expectIdle` ends every test.
- The model never writes code tokens, never sees an AST, never holds the whole tree. Materialization, verification, projection, macros, decomposition, repair = pure host programs (`Agent = G ∘ F`).
- No AE embed; no transport protocols in core; no domain materializers in core (ADR 0015). Plans are data, never prose.
- The filesystem is a projection target, never the actor's interface (ADR 0023): `read` → zoom, `write` → edit move. Whole-file `write` is LEGACY-HOST-ONLY.
- Lint-class repairs are per-project configurable — they route to `dart fix` / custom lint CLIs, never into the meaning surface (disposition 2026-09-06).
- Detour stop: any friction that blocks a pi task twice becomes a named failure class — the surface grows from those, not from guesses. Every new materializer lands with an R7e tiny-model gate (ADR 0024 §5).

## Cleanup / hard-cut ledger

- [x] Production path #1–#7 — DONE 2026-09-04 ([results_r7.md](results_r7.md)).
- [x] 2026-09-06 surface wave — DONE (see [history.md](history.md)).
- [ ] Drop `runTool`'s redundant role if J4's `analyze_check` + spec runner subsume the exit-code oracle for coding tasks (keep for non-Dart hosts).
- [ ] Deferred (evidence-gated, owner: mcp_flutter/intentcall): **H5** — drive a _running_ Flutter app (semantic snapshots, tap, hot-reload) through one MCP tool surface; the harness sees the same `intent_call` shape over a transport adapter (D5). Unblocks after the edit-tier loop proves on-device.
