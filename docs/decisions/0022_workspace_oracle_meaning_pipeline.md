# ADR 0022 — The meaning pipeline grades through the workspace oracle; the vocabulary grows as verified data (bidirectional ETL)

- Status: Accepted
- Date: 2026-09-02
- North Star impact: `amends` — corrects ADR 0019's Consequences claim that
  the code-law violation "closes ONLY via P4 span edits". Written per the
  repo charter (ADR before changing the center).
- Builds on: [0009](0009_goals_as_vectors_plans_as_projections.md),
  [0017](0017_ae_etl_planning_and_a2a_native.md),
  [0018](0018_meaning_view_zoom_projection_context_ownership.md),
  [0019](0019_code_law_absolute_long_horizon_tier.md),
  [0021](0021_problems_as_canonical_rows_project_repair_packs.md)
- Evidence: `pkgs/xsoulspace_agentic_harness/docs/agent/results_stage_p.md`
  (intent tier 0/3 on-device, overseer repair functional but unconvertible),
  `lib/src/meaning/meaning_program.dart` (op set, topology gate,
  materializer), `lib/src/tooling/build_gates.dart`
  (`wireIntentGradedGoal`), `lib/src/benchmark/coding_suite/checkers.dart`
  (`_intents`).

## Context

The intent tier (meaning profile) has never passed a task that was not
pre-wired to it. Tracing the pipeline end to end shows this is not a
prompting or repair problem: the loop is closed in three independent ways.

1. **Oracle closure.** `wireIntentGradedGoal` verifies against a
   host-authored `IntentExpectation` sequence, and the `intents` checker
   replays the same host-authored table (`intent_calls.json`) against the
   materialized program. The verification loop never reads the workspace's
   real tests. The D8 workspace-convention oracle — the thing that makes
   delegated tasks general — is reachable only through the run-graded arm's
   whole-file `write`. That arm is therefore load-bearing for real tasks,
   which is exactly the law violation P4 was meant to close.

2. **Vocabulary closure.** `meaningExecutorOps` is 14 ops
   (`load_arg … error`): no arithmetic (a model literally cannot express
   `a + b`), no comparison beyond `eq`, no string building beyond
   `starts_with`, cycles banned outright (`chainSpecError` — "hard cut
   until evidence demands loops"), and **no `call` op** — a chain cannot
   invoke another intent. Intent-first growth (ADR 0019 §4) therefore
   cannot compound: growth produces more *independent single-chain*
   intents, never programs.

3. **Materialization closure.** `materializeMeaningProgram` emits a generic
   VM replaying embedded JSON (`initialState()` + `runIntent(...)`). No
   imports, no typed signatures, no calls into workspace/package APIs. Even
   placed in the jail, it can never satisfy `dart test` for an
   implementation of anything. There is no bridge from "meaning passes" to
   "workspace passes".

Reinforcing meta-loop: vocabulary can't express real tasks → only pre-wired
tasks run → host-authored expectations suffice → no pressure to build the
Dart ETL → the only arm touching real workspaces is run-graded `write` →
law violation → effort flows to P4 (an editing fix) → generation arm stays
closed → back to pre-wired tasks. Additionally, the current division of
labor asks a 2–4k model to hand-write VM assembly (spec tables of 14
primitive ops) — the task a small model is worst at. Measured: `intent_03`
0/3 at ~20k tokens/run; the overseer repair loop works mechanically but the
mover cannot reliably convert prose notes into spec rows.

## Decision

1. **The workspace oracle IS the intent oracle.** The meaning profile's
   expectation table must be DERIVED from the workspace's failing tests /
   conventions, not authored per task by the host. ETL-in: a Dart adapter
   (the planned `xsoulspace_agentic_dart_meaning`, plus AE canonical rows
   per ADR 0021) turns `dart test`/`dart analyze` failures into intent
   skeletons + expectation rows. The final gate remains the workspace
   convention itself (D8). "Write a tic-tac-toe game in Dart" becomes:
   failing tests are the intents (`winner`, `move`) and their expectations;
   nothing is pre-wired.

2. **The materializer targets idiomatic workspace Dart.** The materializer
   spec is data (per ADR 0019 §1: an invented language = an intent set + a
   materializer spec, both host-verified). The VM-replay contract stays as
   ONE realization (it is the interpreter-parity oracle); a workspace-Dart
   realization (typed functions, imports, package-API calls, file layout)
   becomes the target for the first application, so the final gate is the
   workspace suite. AE owns the canonical form; hosts own realizations.

3. **The vocabulary grows as verified data — now, not later.** Add ops the
   way ADR 0019 §4 prescribes (each op = spec + host-verified semantics in
   the one VM + parity test), sequenced by real failing tasks:
   arithmetic/comparison/string ops first; a bounded-iteration op (the
   existing 1000-step limit bounds it; the topology hard-cut becomes
   "bounded iterations", not "no cycles"); and a **`call` op** so intents
   call intents — without it the self-extending vocabulary claim has no
   composition mechanism. Every op enters through data + validation, never
   a prose vocabulary edit.

4. **Shrink the model's burden with the ADR 0021 pattern.** The host
   decomposes (tests → intent skeletons with typed params/returns); the
   model fills bounded slots (op choices, literals, jump targets) as data;
   the mechanical verifier grades each slot against the derived
   expectations. The model never authors chains from scratch. Prose→spec
   repair conversion (the measured 0/3 failure class) is replaced by
   spec-row repairs selected from validated alternatives.

5. **P4 is reframed, not dropped.** Span-anchored edits close the
   *editing* surface (modifying existing files under the law). The
   *generation* surface (new code from tasks) closes via this ADR's ETL +
   materializer + vocabulary tracks. Span edits become one projection of
   the Dart ETL rather than the closure of the law contradiction. The
   run-graded arm remains a transitional scaffold; new delegation tasks
   should prefer the meaning profile as soon as R6's first track lands.

## Consequences

- Supersedes the ADR 0019 Consequences sentence: "the run-graded arm's
  teaching-prompt contradiction … closes ONLY via P4 span edits — there is
  no profile escape hatch." The law's closure for generation is the
  workspace-oracle pipeline (this ADR); span edits close the editing arm.
- New host package work item: `xsoulspace_agentic_dart_meaning` gains the
  ETL role (tests/analyze → canonical rows → intent skeletons), not only
  span-anchored edits.
- New AE wire work item (bidirectional ETL, per AE's own North Star):
  workspace-oracle rows (`dart/test_failure` class family) and materializer
  specs as data. Design:
  `~/xs/agentic_executables/docs/ae_harness_etl_spec.md`.
- The benchmark suite stops growing pre-wired intent tasks; new intent-tier
  tasks must be derivable from a workspace suite.
- Open language (AE): intent skeletons derived from tests are AE canonical
  rows; capture-back (resolution → durable pack entry) applies to the
  synthesis loop exactly as it does to repair packs (ADR 0021).

## Non-goals

- No relaxation of the code law: the model still never writes code tokens,
  never sees an AST, never holds the whole tree.
- No conversation-log adoption for the meaning profile.
- No speculative general-VM design: every vocabulary/ops addition is pulled
  by a failing real workspace task, never pushed by foresight.

## Validation

- `long_horizon_composition_test.dart` stays green (flatness claim
  unaffected).
- New LLM-free gate: a scripted actor drives a workspace-graded task
  end-to-end (fail tests → rows → skeleton → model moves → materialize →
  `dart test` PASS) with zero model code tokens and zero host-authored
  expectations.
- Parity test extended to the new ops and to the `call` op.
- On-device gate: the intent tier reaches pass@3 ≥ 1/3 on a
  workspace-derived (not pre-wired) task before the head-to-head publishes
  intent-arm numbers.
