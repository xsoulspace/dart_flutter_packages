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
| `harness_verify` per-package convention: the extension cannot derive the ACTIVE package's check automatically | `harnessd_cli.dart` + extension env | `HARNESSD_CHECK` env works; derive the package from the touched files instead |
| Root convention is a MONOREPO compromise (`flutter test` over root test/) | `workspace_conventions.dart` | per-package tasks carry `--check`; the D8 convention stays the default |
| New-task goal isolation on a resumed world | per-workspace snapshot store | the store carried the previous goal; the small model replayed it (Phase 1 dogfood) |
| Bridge crash on cancel during a live tool call | `GenerationState.postToolCall` → `_dispatch_lane_barrier_sync` | callback-after-delete class (Phase 1.5 finding (d)) |

### Untested surface (built, never proven end-to-end)

| Feature | Gate that must run | Status |
| --- | --- | --- |
| REAL-model gates for the new tiers (R7e tiny-model, on-device AFM) | trusted-author `apply_executable`, `edit_section`, `edit_key`, task-grammar pre-pass — each needs one real-model row | named deferred — needs the on-device AFM run |
| Consent plans granted/audited in a REAL pi session | a real session grants one, audits consentLog | unit-only |
| Reasoning beats (`thinking` capture, escalation reuse) | a real-model run exercises them | unit-only |
| `remove_member` (retire) on a REAL model flow | an AFM/OpenRouter retirement attempt | unit-only |
| Pack work-orders (multi-edit consent-once work orders) | — | designed, not built |
| Refactor executables (`rename_package` packs) | — | designed, not built |
| Multi-workspace daemon (last_answer co-tenancy) | — | P4, not built |

### How to work via harness for ALL files (the route, post-2026-09-06)

1. **Dart**: `harness_scan` → `harness_locate` → `harness_zoom`/`harness_impact` → `harness_edit` (replace/insert/remove/apply_executable) → `harness_verify`. Fences: coverage, expressiveness, integration, refs.
2. **md**: `edit_section` — heading-path anchors, byte-precise section splice, 0-broken-links oracle.
3. **yaml/json**: `edit_key` — keypath anchors, comment-preserving splice, parse+semantic-diff oracle.
4. **trusted-author fixes**: a consented `authored_body` pack entry applies via `apply_executable` at zero authored tokens (consent plans: `pack_write` verb; permission waits resolve deny at 45 s — `permission_timeout` — and cancel denies promptly; every decision audited with its path).
5. **everything else** (`other`): visible in the tree, review-gated `write_review` only — by design, never by omission.
6. **The extension of the surface itself** = register a file-class spec + materializer spec (`xsoulspace_agentic_workspace/AGENTS.md`) — the same closed verb surface, more covered reality. Lint-class repairs are OUT of scope by disposition (per-project; `dart fix` / custom lint CLIs own them).

## NOW — the remaining frontier (prioritized)

The pi-dogfooding surface wave of 2026-09-06 landed the mechanical tier, the
discovery ray, the warm tick, the trusted-author tier, the md/yaml/json
materializers, the pack inventory + task-grammar one-decision path,
execution-as-meaning, the VCS projection + live registration seam, consent UX
hardening (45 s deadline + deny-on-timeout, cancel-deny, F3 audit paths, zoom
re-stat), and the AE knowledge plane (gates + counts:
[history.md](history.md)). What remains, ordered:

| P | Item | Status | Gate |
|---|---|---|---|
| P1 | REAL-model gate rows for the new tiers (trusted-author `apply_executable`, `edit_section`, `edit_key`, task-grammar pre-pass) — one on-device AFM session covers all four | named deferred — needs the on-device run | one R7e-style row per tier |
| P2 | One decision, one program (ADR 0030): `meaning_program` — model-emitted read chains (locate→zoom→impact→read) in ONE call, single-cursor dataflow, format-blind (the node's class routes the host reader), fail-fast named bounces, result-cut verdicts. **LANDED, GATED** — surface-convergence row measured: converged profile 5 tools / 1,537 est tokens vs current 6 / 1,598 (the profile SHRINKS when the program graduates — replaces zoom+impact). Gates: `meaning_read_program_test.dart` 7/7, overhead-convergence row. NAMED, NOT BUILT: mutation ops behind a verified on-device row; program-mode flatness rows (`tool/afm_flatness_probe.dart`); daemon registration | on-device program rows + graduation |
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
   by design.
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
