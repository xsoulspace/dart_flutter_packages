# ADR 0016 — Measure tool efficiency; keep the tool surface minimal and composable

- Status: Accepted
- Date: 2026-08-27
- North Star impact: `clarifies` — tooling should be *evaluable* and *child-like*
  from the model's perspective (few, orthogonal, composable tools whose
  internals the LLM need not know).
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0014](0014_composition_surface_and_discovery.md),
  [0015](0015_domains_live_in_hosts_core_stays_generic.md)
- Related: `pkgs/xsoulspace_agentic_harness/lib/src/observation/tool_metrics.dart`,
  `bin/tool_eval_profile.dart`

## Context

A small (2–4k context) local model has a precious decision budget. Named tools
are part of the prompt and of every projection; redundant tool *shapes* waste
that budget in two ways: (1) more tool names to reason about, (2) the model
must know *which* near-variant matches the intent. We found real examples:

- `rename_symbol` and `rename_symbol_multi` differ by **one optional array
  param** (`extra_files`), forcing the model to enumerate referencing files —
  a *discovery* job that belongs to the tool, not the LLM.
- A rename is expressed across multiple symbols, prompting the model to
  choose wrong among near-tools.

Before deciding what to simplify we had no per-tool measurement: no first-use
success, no in-sequence position, no cost per call, no failure streaks. ADR
0004's attribution is *per decision*, not per tool. So tool design was driven
by intuition, not evidence.

## Decision

1. **A measuring [ToolRegistry] wrapper is always available.** Wrap a registry
   (whatever decision path) so every tool call records a `ToolCallRecord`:
   name, sequence index, first-use flag, success/error-code, arg/result size
   (≈prompt+generated tokens), latency. `analyzeTools` produces a per-tool
   efficiency report (first-use-ok, success rate, avg cost, latency, max
   failure streak, sequence-position ranks, transitions).
   `observation/tool_metrics.dart` + `bin/tool_eval_profile.dart`.

2. **Simplify toward "child's play."** A tool's *surface* should let the LLM
   state intent plainly and not force it to do the tool's own discovery or
   plumbing. Concretely this round:
   - Merge `rename_symbol` + `rename_symbol_multi` → **one** `rename_symbol`
     whose referencing files are **auto-discovered** across the jail (the model
     just says "rename X to Y… and it works").
   - Remove the redundant `_multi` from the default surface (kept as a
     deprecated alias for any host still calling it).

3. **Simplify by measurement, fast round-trip.** Before removing/merging a
   tool, run the measuring profile on a representative sequence; keep the
   report as the justification. Tool changes are validated with the existing
   harness tests + coding-suite smoke, all LLM-free.

## Non-goals

- Not removing every tool — many are genuinely orthogonal (read / write /
  list_dir / grep / glob / locate / patch / rename / verify).
- Not over-collapsing distinct operations (e.g. grep (content) vs glob (path)
  vs locate (symbol index) are different; keep them).
- Not a tool-per-domain proliferation (ADR 0015: domains compose generic
  shapes; tools stay generic).

## Consequences

- Tool simplifications are now **measured**, not guessed: run the profiler
  before/after and read first-use/cost/streak differences.
- A smaller, composable surface fits the tiny-context budget (fewer tokens in
  the prompt, fewer wrong-tool decisions).
- The tool surface is re-measurable in future (any host can instrument its own
  registry) without core changes.