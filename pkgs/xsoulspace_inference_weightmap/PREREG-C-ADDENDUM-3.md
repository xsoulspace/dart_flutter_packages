# PREREG-C — Addendum 3 (2026-11-08): saturation precondition on certification eligibility

Status: FROZEN 2026-11-08 (owner decision granted 2026-11-07 "implement all
stages and apply recommendations"; the plant-3 NULL_LEAK mechanism from
receipts/V1-v2-nulls.jsonl seq 17 is the motivating verdict). This addendum
amends CERTIFICATION ELIGIBILITY only — the frozen certifier
(`tool/runs/a3_score.dart`, certification_rule_frozen in
cells_frozen_A3.json) is UNTOUCHED; the precondition is a gate applied to its
scored output, per the frozen-oracle law (nobody edits their own checker).

## The defect (measured, plant-3)

`certified(arm) := loop_rate(R) < loop_rate(M) AND task_success(R) >= task_success(M)`
is trivially satisfiable when the MIRROR battery M sits at the loop ceiling
(loop_rate(M) = 12/12: every G2 cell cap-hits) and the task floor
(task_success(M) = 1/22): then ANY perturbation of the mirror — including a
null edit — reduces loop-rate and preserves the floored task rate. plant-3
certified 2/4 nulls through exactly this shape. This is the second named
null-leak mechanism (v1 = geometric confound; v2 = saturated mirror).

## Frozen rule (applies to every V-1/V-2 certification from this row forward)

ELIGIBILITY is evaluated on the MIRROR battery M of each edit, at scoring
time, from the same a3_score.dart receipt:

- loop headroom: `loop_rate(M) <= 10/12` (at least 2 of the 12 G2 cells
  NOT cap-hitting on the mirror);
- task headroom: `task_success(M) >= 3/22` (at least 3 of the 22 G0+G1
  task cells passing on the mirror).

An arm (plant or null) whose mirror fails either clause is recorded
**NOT_ELIGIBLE_SATURATED** in the verdict payload: its battery data stays in
the denominator journal (rows are never deleted), but it is EXCLUDED from
certification counts and from null-floor tallies. A plant whose mirror is
not eligible cannot produce a certified edit this stage; the honest verdict
for that plant is NOT_ELIGIBLE_SATURATED (a measurement of the plant's
severity, not a pipeline failure).

Family-wise tallies are recomputed under eligibility: the governing number is
`certified_count / eligible_count`; the pre-amendment tally (2/8,
[0.071, 0.591]) remains on record unchanged (append-only law) and is
explicitly superseded for future claims.

## Procedure

1. Score mirror + removal batteries with the FROZEN certifier (unchanged).
2. Apply this gate to the scored receipt (pure function of loop_rate(M),
   task_success(M)); the gate writes `eligibility` into each arm's verdict
   row: ELIGIBLE | NOT_ELIGIBLE_SATURATED(loop_clause|task_clause|both).
3. Null-floor rule unchanged (0 of 4 nulls certified per edit) but computed
   over ELIGIBLE nulls only; a NOT_ELIGIBLE_SATURATED null is journaled and
   excluded, never counted as clean.
4. Past verdicts (A3, V-1 v1/v2 plant-1/plant-3, V-2) are NOT re-adjudicated.

## Scope

V-1 (all plants, family-wise subset {plant-1, plant-3, plant-5} now extended
by the resumed plant-4/6/7 batteries), V-2 mechanism splits, and any future
arm reusing the certification rule. G-3 revision-dynamics arms are NOT
certification-bearing (PREREG-G §6.6) and are unaffected.
