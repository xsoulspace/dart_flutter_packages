# ADR 0013 — Native tool calling is the default decision path; guided schema is an explicit exception

- Status: Accepted
- Date: 2026-08-27
- North Star impact: `clarifies` — hardens the "harness = intelligence amplifier"
  mechanism by ruling on *how* tool calls cross the model boundary.
- Builds on: [0007](0007_extensibility_seams_and_conformance.md),
  [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0012](0012_extract_agentic_harness_package.md)
- Supersedes: the C2 (decision-path) confound documented in
  `pkgs/xsoulspace_agentic_harness/docs/agent/plan_fair_pi_comparison.md` —
  this ADR records the resolution, the plan doc's "landed" note, and the
  runner defaults that were the subject of the A1 comparison.

## Context

The 20-task coding suite surfaced three confounds (C1 client input shape, C2
decision-path split, C3 no pi column). C2 was the dominant one and is now
quantified:

- **Guided schema** (`StructuredToolDecisionHandler`): every decision forced
  through an act-vs-answer JSON schema. Same model, same tasks: **0/20**, with
  only 2 total tool calls.
- **Native provider tool calling** (`DefaultGenerationHandler`): **6/20**, 262
  tool calls, with clean single-per-task successes (e.g. `edit_05_write_new_file`
  in 2 calls / 1 tool).
- **pi SDK native loop** (same model): **19/20**.

Same model, identical tasks/retries. The difference between 0/20 and 6/20 is
entirely how tool calls and messages cross the model boundary — not model
capability.

The full matrix, table, and failure modes live in
`docs/agent/results_comparison.md`.
The factorial probe on Apple Foundation confirmed the same shape on-device:
`edit_01_rename_constant` via the native arm = **1 decision, PASS, ~600 cum
tokens**; via guided = 17 decisions / ~15k cum tokens / FAIL (see
`docs/agent/results_plan_falsification.md` §real-model and M6.1).

## Decision

Make **native provider tool calling the default decision path** everywhere a
provider/model supports it. Guided schema is **only** an explicit, opt-in
exception when the model cannot emit native tool/structured calls.

Rules:

1. Runner/bus defaults are native. The `--decision guided` flag, and the
   probe entrypoints that intentionally measure plan/decomposition via guided
   generation, remain as opt-in.
2. The OpenRouter client uses the native chat-completions `messages` codec
   (`SituationMessagesCodec`, `useMessagesCodec: true`) by default — not the
   flattened `CONTEXT:` single-user-message shape (C1).
3. Tool schemas are passed natively as real `functions`/`parameters` schemas;
   the internal kind-tagged format is translated via schema bundle. Guided
   schema is never used as a backstop for native tools.
4. Any new A/B that must flip to guided (or any new "framework-breadth")
   decision path starts by stating why native cannot serve, and the column is
   labeled with the decision path (standing rule already in the North Star:
   "states backend / decision path / tokens source / tool surface").

Non-goals: this ADR does not decide the *composition-surface API* (declarative
loops / evals / datasets). That is a separate design (see
`docs/agent/composition_surface.md`). It also does not relax the LLM-free
testability or determinism invariants (ADR 0003, 0007).

## Consequences

- Consistent, reusable experiments: a native-by-default suite + codec default
  means the harness's measured-claim columns are directly comparable; the
  C2 confound no longer silently corrupts new numbers.
- Guided escapes remain available and labeled, so decomposition probes (which
  explicitly test guided reasoning) keep working.
- Doc drift to update: any doc/plan snippet citing "guided = default" or
  publishing a 0/20 table as the harness baseline (see `{{`, the A1 table,
  `results_comparison.md`) must be reconciled to native-first numbers.

## Validation

- The native arm is covered by `benchmark/runs/afm_ops_edit01.jsonl` and the
  suite matrix. CI runs the scripted suite (`--backend scripted`) which stays
  native-shaped.
- The codec has unit tests (`test/situation_messages_codec_test.dart`).
