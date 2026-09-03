# ADR 0021 — Diagnostics are AE-ETL canonical rows; repairs are project-guided packs, never core tables

- Status: Accepted
- Date: 2026-09-02
- North Star impact: `clarifies` — applies the AE-ETL shape (ADR 0017) to
  diagnostics and closes the R1 failure mode (448k tokens to fix a lint).
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0015](0015_domains_live_in_hosts_core_stays_generic.md),
  [0017](0017_ae_etl_planning_and_a2a_native.md),
  [0020](0020_cut_composition_api.md)
- Related: `agentic_executables_wire` (new `problem_wire.dart` contract),
  `pkgs/xsoulspace_agentic_harness/lib/src/tooling/problem_board.dart`,
  `pkgs/xsoulspace_agentic_harness/lib/src/tooling/mechanical_repair.dart`

## Context

The R1 self-improvement cycle failed on its own terms: a broad multi-file
lint task burned 24 decisions / 448k tokens and produced no edits, and the
operator took two fixes manually. Root cause was NOT model capability — it
was representation and ownership:

1. **Raw diagnostics reached the model as prose.** "Unused import at line
   32" is a concrete instance of an abstract class (*stale import edge*)
   with a deterministic repair. Raw shadows force exploration; exploration
   in a large workspace exceeds bounded cuts by construction.
2. **Repair knowledge had no home.** There was no layer where "this class
   resolves this way, once" could be recorded and reused — so every
   instance re-cost full price, and the operator's manual fix bought
   nothing for the next occurrence.
3. **A core-owned repair table was considered and REJECTED.** Every project
   has its own lints, linters, custom rules, severities, and conventions;
   the *right* repair for a diagnostic code is project domain. A built-in
   code→fix table is framework breadth — the exact gravity drift ADR 0015
   forbids.

## Decision

1. **Diagnostics are an AE-ETL source.** The same chain ADR 0017 built for
   specs — raw → heuristic extractors → canonical matrix → tiered verify —
   takes analyzer/linter output as a new raw source. New wire contract in
   `agentic_executables_wire` (`problem_wire.dart`): `ProblemRowWire`
   (canonical row: class id, severity, span, evidence, source) and
   `RepairExecutableWire` (project-declared deterministic repair keyed by
   class id). AE owns the semantics; hosts consume the shapes (D2).

2. **Two different layers, deliberately separated:**
   - **Format adapters** are generic and syntax-only: one per tool output
     *format* (Dart analyzer machine format first; other languages are OUT
     OF SCOPE until the Dart loop is proven). An adapter canonicalizes
     syntax; it knows nothing about repairs.
   - **Repair packs are project-guided.** A pack maps canonical class ids →
     repair executables (`delete_line`, `delete_span`, `replace_span`,
     `command` — project-defined deterministic argv, no shell). Packs live
     with the project (graduating to AE pack machinery / intent registries
     later); the harness knows only the contract: canonical row in →
     executable or null out. **The model never chooses the executable.**

3. **Three repair tiers, per class:**
   - **Mechanical** (pack executable exists): the harness applies the span
     transform, then the SOURCE ANALYZER re-runs as the free oracle —
     exit-clean closes the problem node; any failure reverts (host keeps
     prior content) and escalates. Zero model tokens.
   - **Meaningful** (no executable): ONE decision with a span-zoom cut
     (problem + span + neighborhood — no exploration). The resolution is
     then CAPTURED into the project pack: a novel class is resolved once
     and automated forever. This is the self-improvement loop in AE form.
   - **Human** (non-falsifiable): evidence surface, per the eval-tier
     honesty rule.

4. **Scope:** Dart adapter only. Kotlin/Swift/other adapters are out of
     scope until the Dart loop proves the shape end-to-end.

## Consequences

- The board (N1) becomes a **projection of the canonical matrix**, not a
  raw-diagnostics lister; tasks surface only for classes without
  executables.
- Economics: extractors 0 tokens; canonicalization 0 tokens; mechanical
  tier 0 tokens (majority class); meaningful tier one decision per NEW
  class. The 448k failure becomes structurally impossible — there is
  nothing for the model to do for known classes.
- Per-project lint diversity becomes an adapter+pack backlog, not an agent
  problem; custom linters emit custom class ids that project packs map.
- Mechanical repairs are conservative: span-exact, verified by re-analysis,
  auto-revert on verification failure. Trust per class is earned by the
  verification track record.

## Non-goals

- No core-owned or harness-owned repair tables (rejected — project domain).
- No Kotlin/Swift adapters yet.
- No shell interpolation in repair commands (argv only).
- No model selection of executables (the model proposes at most via M0b
  `declare_check`; the pack decides repairs).

## Validation

- Wire contract tests in `agentic_executables_wire`.
- Harness: adapter → board; pack matching; mechanical repair with
  re-analysis oracle and revert path — all LLM-free.
- Live: the next analyzer-warning batch on the harness's own lib/ resolves
  at ~zero model tokens for known classes.
