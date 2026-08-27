# Agent Harness — Plan

> Forward/frontier record only. Landed work lives in
> [history.md](history.md); durable decisions in the
> [ADR Index](../../../../docs/decisions/README.md); benchmark numbers in
> `results_*.md`. Goal: prove + harden the tiny-context (2–4k) cinematic multi-actor harness. Thesis: harness = intelligence amplifier; model =
> replaceable reasoning primitive.

**Status (2026-08-27):** native tool calling is the default (ADR 0013);
P1 (edit-quality gap) is opened via ADR 0009 decomposition with
−44…−72% cumulative-token wins at equal pass rate (scripted refactors).
P2/P3 direction set by [ADR 0014](../../../../docs/decisions/0014_composition_surface_and_discovery.md).
This document tracks only what is _next_.

---

## Near-term frontier (ordered)

### P1. Edit-quality gap (harness 6/20 → wants 19/20 parity)

Decision-machinery confound (C2) is resolved; the residual gap is **edit
quality, not decision machinery** (11/14 failures classified `wrong-edit`).

- [in-progress] Goal/Step entities (ADR 0009 §2–4): `Goal` with tool-callable
  success criteria; `Step` entities on a verifiability spectrum
  (`mechanical | observable | open`). Real-model decomposition probe
  (`bin/coding_suite_decomp_probe.dart`) under cumulative-token accounting.

### P2 — Tool-surface breadth: discovery (the measured ceiling)

Current jail is read/write/list_dir (+ patch/rename). **No search.** A single
`edit_01` cost 17 tool calls because the model had to recursively `list_dir`
to locate a file. For a 2–4k model the budget dies on discovery, not on the
edge layer.

- [DONE Stage 1] jailed `grep` / `glob` (seam-3 tools) for cheap find —
  `fs_tools.dart`, `test/discovery_tools_test.dart`.
- [DONE Stage 1.5] structural `locate` ray-cast (`tooling/locate_index.dart`)
  — deterministic identifier index, defs-first, jailed, JSON-serializable;
  `test/locate_index_test.dart`.
- [DONE Stage 1.6] **tool-efficiency measurement** (`observation/tool_metrics.dart`)
  + `bin/tool_eval_profile.dart` — a measuring [ToolRegistry] wrapper that
  captures every call (native/guided): first-use, in-sequence position,
  reuse, cost-per-call (chars≈tokens), latency, failure streaks, transitions.
  `analyzeTools` → efficiency report. Used to rank tool simplification.
- [DONE Stage 1.7] **simplify tool surface** — `rename_symbol` unified with
  `rename_symbol_multi` into ONE tool that auto-discovers referencing files
  (the model no longer enumerates them); removed from default surface.
  [follows] Budget-aware discovery: keep the cut token-bounded.

### P3 — Composition surface: declarative loops + eval/datasets (ADR 0014)

General agent direction: coding **and** long-form (article / screenplay /
book) **and** long conversations, all exported as **data** — logic, tools,
schemas, loops declared declaratively, eval/datasets declared once and run
many ways (scripted / native / guided / pi-proxy).

- [DONE Stage 2] Declarative `FlowSpec` (closed `StageSpec[]` + `ToolSurface`
  gate + free-form `archetype`) + `renderFlow` → `DecisionFlow`; `DatasetSpec`
  (`passable` vs `evidence` tiers) — `lib/src/composition/` and
  `test/composition_surface_test.dart`.
- [CLOSED via ADR 0015] **Content targets** are NO LONGER a harness phase.
  Dialogue/screenplay/book/coding are *host domains above the seams* — the
  harness core interprets no archetype. A host embeds via the existing public
  surface (`AgentWorldSetup` + `HarnessLoop`); general/parallel work uses ACP.
  `test/composition_dialogue_e2e_test.dart` stays as a **host-side demo** of
  how a domain (e.g. `last_answer`) composes a loop, not as a core feature.

### P4 — Fair-matrix re-run under cumulative tokens

Phase-4 matrix under honest cumulative-token accounting is outstanding
(ADR 0004 §7). Re-run `harness+AFM`/`harness+OR` (native + codec) vs `pi+OR`
with riding columns, now that native + codec are defaults. Headline still
pending: `results_comparison.md` (AFM 5/20, OR 4/20; columns were not
comparable — C1/C2/C3).

---

## Standing rules

- Every published column states backend, decision path, tokens source, the
  tested tool-surface. Failures are data.
- Escalation-rate metric ships beside every pass-rate table.
- Extensibility ledger: three host entries vs the same seam → design
  conversation (ADR 0007).
- Gravity: (a) tiny model stays useful, (b) fewer LLM calls, (c) context
  bounded + derived, (d) LLM-free testable.
- Native tool calling is the default; guided is opt-in only (ADR 0013).
- Scope tripwires (A2): no replanning policy engine, no plan-schema
  versioning, no planner agent. Steps in, projection out, checks fail loudly.

## Cleanup / hard-cut ledger (CI-mode)

Following engineering-stewardship practice, cut as we go:

- [ ] Delete legacy manual-schedule tests that would have masked the idle-race
      class of bug; keep only production-path (`runUntilIdle`) tests from the
      postmortem.
- [ ] Remove dead/bisection probe bins (`bin/probe_*.dart`,
      `benchmark/debug_*.dart`) after lessons are folded into checks/tests.
- [ ] Fold `composition_surface.md` "design note" framing into the accepted
      ADR 0014 stance; the note stays as a frontier detail doc, not a wish-list.
- [ ] Trim the `benchmark/runs/` tracked-or-not evidence: keep per-backend
      traces, drop throwaway `probe_verbose.jsonl`.
