# PREREG-G-STAGE2 — G-3 pathology cells (unsolicited loops), FROZEN 2026-11-08

Status: FROZEN before any stage-2 arm run. Extends PREREG-G.md (stage 1,
EXECUTED: INSTRUMENT_VALIDATED + NO_ARM_MOVES_CAP_HIT on SOLICITED loops +
G0_GUARD_FLOOR_NO_HEADROOM named). Stage 2 answers the question stage 1
could not: does sampler-side revision move the loop phenotype on cells where
the base loops WITHOUT being asked (the A2/P-2 pathology: base cap-hits
91.7% @4096, 80/88 @1024)? Still NO certification (PREREG-G §6.6 carries
over): movement here = pathology-repair CANDIDATE; certification belongs to
a stage 3 with disjoint cells.

## 1. Cell selection (base-behavior-conditioned, frozen before arm runs)

Source pool: the paper's exp8 `math_train.jsonl` (7,275 rows; fetch recipe =
the P-2 pool recipe recorded in receipts/P2-run.jsonl; network-required;
failure = named PATHOLOGY_POOL_UNAVAILABLE, arm staged not forced).

- Pathology candidates: first 48 rows in file order, rendered per
  PRACTICE_RENDER_SAME_AS_A2 (problem + '\nPlease reason step by step, and
  put your final answer within \boxed{}.', thinking chat template, one-lined
  for the line-based prompts protocol). Base greedy probe @cap 1024 on the
  Qwen3.5-0.8B base snapshot. Selected cells = FIRST 12 in order with
  cap_hit=true (expected ~11/12 by the base rate; if fewer than 12 qualify,
  take all qualifiers and record SHORT_SELECTION with the count — never
  pad).
- Guard cells: the 12 G1 perm-corpus cells from tool/runs/cells_frozen_A3.json,
  base greedy probe @cap 64; selected = FIRST 8 in order where base PASSES
  (guards with measured headroom — directly fixes the stage-1
  G0_GUARD_FLOOR_NO_HEADROOM defect). If fewer than 8 pass, take all
  qualifiers, named SHORT_GUARDS.
- Both selections land in `tool/runs/cells_frozen_G3_stage2.json` with
  group names REUSED ('G2' = pathology cells cap 1024, 'G0' = guard cells
  cap 64), lineage.source naming probe + seed + pool digest, sha256
  recorded in this file's frozen header below (filled at freeze time, before
  any arm run).

FROZEN CELLS SHA256: (recorded at freeze; the runner verifies at launch —
mismatch = named refusal CELLS_DIGEST_DRIFT).

## 2. Arms and rules

Arms: R0, R1, R3 PRIMARY; R2, NULLA SECONDARY (run only if device budget
remains; stage-1 facts: embeds path good, R3 mechanism good). Constants,
detector, movement clauses (Δcap-hit ≥4/12 ∧ loop-signature same-direction
≥25% rel), guard rule (G0 success < R0 − 1 = GUARDRAIL_FAIL), kill rule
(R1 moves ∧ R2,R3 within 1 cell ⇒ SAMPLER_GENERIC), determinism cross-check
(R0 re-run first 4 pathology cells exact), key law, POWER gate, lock v3,
scratch law: ALL identical to PREREG-G §1-§6 (referenced, not restated).
Headroom precondition §6.1 is INHERENT here (cells selected cap-hitting);
if R0 < 12/12 on the frozen set → named SELECTION_LEAK row and stop.

## 3. Additive implementation surface (frozen shape)

`--expect-cells-sha` argument added to g3_revision.py AND g3_score.dart
(default = the stage-1 frozen constant, so stage-1 behavior and tests are
byte-identical; regression = stage-1 suites green). Group names and caps ride
the cells file; no other logic changes.

## 4. Verdict semantics (frozen)

Possible outcomes, each a full verdict with denominator:
- MOVEMENT on R3 (cap-hit down ∧ signature same-direction) with R1 NOT moving
  ⇒ revision-specific pathology repair candidate (named
  REVISION_SPECIFIC_CANDIDATE); feeds stage 3 only via new prereg.
- R1 also moves ⇒ SAMPLER_GENERIC on pathology cells (the cheap honest
  verdict).
- No arm moves ⇒ PHENOTYPE_ROBUST_TO_SAMPLER (the attractor is not the AR
  ratchet alone; weight-side L1 remains the only proven repair class).
- Guard: any arm degrading guards vs R0 ⇒ GUARDRAIL_FAIL for that arm.
- Determinism drift ⇒ INSTRUMENT_UNVALIDATED. PARTIAL-with-denominator
  allowed (budget stops between arms/cells; resume-safe).
