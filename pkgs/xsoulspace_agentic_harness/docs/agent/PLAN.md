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
| P0 | **THE ON-DEVICE WAVE RE-RUN** — EXECUTED 2026-09-07 (see `afm_wave_results.md` § P0 RE-RUN). Row 1 PASS 1/1 at HALF the 2026-09-06 tokens (2,024/1 decision/24.5 s) — `end_after_tool` proven on-device. Rows 2–4 died in ONE NEW SYSTEMIC CLASS: **opaque schema-invalid tool calls** (`ToolCallError` → bare `generation_error` → same-cut retry — the call never reaches Dart, so the ADR 0034 named-bounce contract cannot fire; 18/8/10 ToolCallErrors per row, loops of 59–109 generations, uncontained by maxToolRounds) | **P1 is now the ToolCallError fix** (named `tool_args_invalid` code + bounce-class beat, never a retry); then rows 2–4 re-run — that run measures whether the tiny model RECOVERS through class-teaching bounces, which is the graduation measurement for the union enum itself (if not, the enum splits per class — a measured surface change) |
| P1 | **Opaque ToolCallError class (the P0 finding)**: the bridge catches `ToolCallError` → NAMED `tool_args_invalid` (tool + framework detail); the harness records it as bounce-class data (a named beat: required slots per class) — never a same-cut retry; maxToolRounds must count failed generations too | **UNIT-GATED 2026-09-07** (bridge classification on BOTH generate paths + harness named bounce beat + failed-generation round counting; gate: `test/tool_args_invalid_bounce_test.dart` 3/3 + `check_bridge_swift.sh` unit 27/27) | rows 2–4 re-run: the bounce loop teaches recovery (or the enum splits per class — measured) |
| P1 | **Native-truth pre-flight**: the 1.45 factor is a measured APPROXIMATION on JSON-heavy content. The durable fix is named in the client already (`model.tokenCount(for:)`) — expose it over the bridge (`xs_fm_token_count`) and pre-flight with native truth; the equation keeps its shape, the factor term goes to 1.0 (config default stays until measured) | named (R9.1), not built | derivation row vs native baselineTranscriptTokens agreement ±5% over 10 runs |
| P2 | **`surface_capability_diff` gate**: when a verb is ABSORBED, mechanically diff the absorbed verbs' arg space against the survivor — the creation regression (the unified verb could not CREATE keys) would have been named at unification time, not by hand (surface_gaps 2026-09-07) | gap logged, not built | the gate runs on every surface change; any lost capability is a named row |
| P2 | **Wave instrument: split the failure classes.** The 2026-09-06 rows conflated overflow loops with model scan-loops; the summary must classify `decision_dropped` (window) vs repeated-identical-moves (task framing) vs final-gate misses — an instrument that cannot distinguish them misattributes the next run | not built | summary rows carry the class; n>1 per row |
| P2 | Speculative verify actor; topology engine; registry linter (unchanged from 2026-09-06 — designed, not built) | designed | per-row gates below |
| P3 | **`edit_node` rename** (ADR 0034 disposition 2): string-mechanical, 87 refs, token-neutral — lands in the SAME batch as any fix the P0 run forces, never mid-flight (conflict hazard with parallel unification work) | deferred, trigger = P0 landed | rename lands; gates re-run green; no re-measurement needed |
| P3 | **Mutation ops joining `meaning_program`** (ADR 0034 disposition 3): trigger = a P0/P1 row where read/edit alternation dominates tokens/decision. NOT a wiring task — the three design constraints are recorded in ADR 0034 (transactional all-or-nothing; consent scoping; the program IS the move) | deferred, design recorded | the trigger row + the three constraints implemented together |
| P3 | AE knowledge plane completion; multi-workspace daemon (unchanged) | named | per-row gates below |
| P1 | **ADR 0035 binding registry (the format seam, pre-TS/C#)**: promote the proven `perform` contract to the tiny `MaterializerBinding` record; router dispatches via registry (the `switch (node.kind)` dies — routing keys on the node's stamped `class` prop); registration-time validation (binding↔spec agreement, extension disjointness, actions⇒oracle, anchor currency); mechanism-first unknown-id bounce (per-class truth lives in `edit_actions`/`anchors` props, zero recipe prose) | designed (ADR 0035 §1/§3/§5), not built | edit_node_unified + span_edit_gate suites green; bounce strings carry no per-class recipes |
| P1 | **ADR 0035 fs-tier map ownership**: `fs_etl` calls `binding.mapBuilder` in the zero-model-token pass (`_mapClasses`/`_mapPrefixes`/index switch die); budget caps + `map_skipped`/`map_truncated` stay ENGINE-owned; sub-node id prefix is binding-declared (stale-map drop ownership) | designed (ADR 0035 §2), not built | orphaned-sub-node gate test (edit a mapped file → no stale sub-nodes); etl_tick green |
| P2 | **ADR 0035 span_editor safe decomposition**: lexical utils → `dart_lexicon.dart`; pack registry → `edit_pack.dart`. The apply-engine unification with span_editor is DEFERRED (trigger: a measured row proves baseline/approver/atomicity parameterization isn't a fork — MoE verdict); md/yaml apply skeleton merges only at the 3rd verbatim copy | designed, not built | span_edit_gate + pack_edit_gate + edit_pack_capture green after each mechanical move |
| P2 | **Language families: TS then C# (the next operation, ADR 0035 §6)** — Tier B day one (tsconfig/package.json via the json class; csproj via a new xml binding), Tier C v1 = mechanical symbol scanner + pack-fed bodies (`apply_executable`) + analyzer oracle (`tsc --noEmit` / `dotnet build`) + test convention; NO model-composed bodies until v2 op-chain back-ends (evidence-gated). HARD GATES: zero-arg-delta (`{action, symbolId, body?, anchor?}` forever); ts/c# reuse dart action names verbatim; no format literal in router/bounce strings; registry-lint + `surface_capability_diff` pass at registration | designed (ADR 0035), not built | graduation re-measure: cutBudget ≥ 628 fits=true with ts+c# registered; R7e tiny-model gate per class (one real ts edit, one real c# edit through the ONE verb); P0 rows 2–4 re-run (union-enum graduation) |
| P2 | **tree-sitter ETL-in (named, evidence-gated — ADR 0035 §7)**: no FFI dep until (1) ≥3 named mechanical-scanner failure classes, (2) a measured workaround-cost row, (3) a spike proving grammar→meaning nodes with zero host-authored expectations, (4) budget proof the 4k tier still fits | gate recorded in ADR 0035; not built | all four clauses met; otherwise the gate stays |
| P2 | **tree-sitter spike (ADR 0035 §8 — separability scope, one grammar)**: `xsoulspace_treesitter_raw` (the ONLY dart:ffi import, LEAF pkg, zero workspace imports) + `SourceParser`/`ParserConformance` seam + span bridge (UTF-8→UTF-16→source_span, multibyte golden tests) + generic query+map interpreter + TS mapping table (member symbols day one) + conformance battery run against BOTH the mechanical TS scanner and the FFI impl — the conformance DELTA is the clause-1 evidence, measured as data | scoped (ADR 0035 §8), not built | results row `results_etl_grammar.md`: clauses 3–4 pre-seeded (zero-host-authored mapping + budget proof); clauses 1–2 stay open pending REAL task rows — no FFI dep in the workspace regardless |
| P2 | Speculative verify actor: run-node world-fork primitive (beat watermark), outcome-beat arbitration (canonical wins, `speculative: true` flag), shared `RunMeaningExecutor` reusing `runTool`'s allowlist verbatim | designed (lane F report, 2026-09-06), not built | speculative-vs-canonical disagree → rollback e2e |
| P2 | Topology engine: task-declared `{worlds, actors, roles, model-tiers, budgets}` as data; meaning-part actors (zero-token, scripted handlers — same loop, beats, budgets) | designed, not built | topology selection e2e |
| P2 | Surface ergonomics (P0.5): registration-time linter over `ToolDef`s enforcing the R7e rules (required anchor slots on the wire, mechanical label resolution, bounces carry repairs) | not started | registry-lint gate |
| P3 | AE knowledge plane completion: harness-side host adapter (export → `MeaningNode` world state); remote hub fetch/push + trust/signing model; `ae know` subcommand family per the AE repo's `docs/ae_know_design.md` | CLI + local hub landed; adapter/remote named | hub round-trip against a LIVE harness world |
| P3 | Multi-workspace daemon (last_answer co-tenancy) | not built | co-tenancy e2e |

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
