# PREREG-C — Phase C (frozen 2026-11-05, pre-result)

Arms V-1, V-2, V-4. Floors below are FROZEN; changes require a new prereg row.

## V-1 · Matched-null control arms
For each certified edit produced by A3/WS-0 (denominator D edits), run the
identical certification pipeline on four matched nulls:
1. random Gaussian direction, matched norm, same columns;
2. shuffled version of the recovered direction (same spectrum, wrong geometry);
3. unrelated-concept direction (a different contrast pair's mean difference);
4. quant-noise-matched perturbation (bf16 requant noise of matched magnitude).
- Floor: **0 of 4 nulls certified per edit**. Any certified null = NAMED
  `NULL_LEAK` → pipeline HALT; the halt and its denominator are the verdict.
- Family-wise: across all edits, null certification rate reported with Wilson CI.

## V-2 · Effect/mechanism split
Per certified edit, three interventions on the claimed circuit:
(i) ablate claimed columns (zero the delta there) → effect must die (loop-rate
delta returns to base within pre-registered tolerance);
(ii) restore → effect returns;
(iii) relocate the delta to control layer 8 → effect must die.
- MECHANISM verdict = PASS only if all three hold; EFFECT verdict = held-out
  generalization battery delta, recorded SEPARATELY. An edit with true effect
  and false mechanism is logged as `EFFECT_TRUE_MECHANISM_FALSE` — a distinct,
  valuable outcome class, never merged into PASS.

## V-4 · Red-team refusal bench
N=12 planted fake wins at scorer tier (fixtures, no model needed):
6 format artifacts (win only under format-sensitive scoring: fence-only,
trailing-pad, label-case), 4 length tricks (verbose inflation of raw counts),
2 battery gamers (memorized cell answers).
- Certification rule under test: an edit's evidence must survive
  `formatInvariantScore` and `lengthNormalized`; memorized-answer cells are
  excluded from certification evidence by probe bookkeeping.
- Floor (scorer tier): **12/12 named refusals**. Below floor = scorer-freeze
  defect → re-freeze via new prereg row before any model-tier run.
- Model tier (post-A3): any edit whose certification evidence vanishes under
  the invariance wrapper is refused with NAMED `FORMAT_ARTIFACT_SUSPECT`.

## Kill clauses
NULL_LEAK → halt edits, record halt. V-4 scorer tier < 12/12 → freeze defect.
Neither kill invalidates already-recorded A3 measurements (they stay in the
ledger with their denominators).

## Addendum 2026-11-05 (case blind spot; frozen scorer unchanged)
The V-4 scorer-tier run met 12/12 but with a documented coverage split: the
two label-case plants die only under case variants (lowercase_all /
uppercase_all), NOT under the frozen four perturbations (frozen-four-only
counterfactual = 10/12, recorded in receipts/V4-scorer-tier.jsonl). The frozen
four stay frozen: global case perturbations would wrongly penalize
case-SENSITIVE instructions (uppercase-title cells). Pre-registered instead:
- V-4 MODEL tier (post-A3) applies case-variant perturbations to text-label
  cells only (math/numeric cells keep the frozen four); a certification whose
  evidence dies under a cell-typed case variant is refused
  `FORMAT_ARTIFACT_SUSPECT:case`.
- Coverage argument for the interim: our certification text cells (slugify,
  tool-call) carry cell-specific frozen checkers whose specs already fix case,
  so case artifacts cannot certify through them; the blind spot is generic-
  wrapper-only. This argument is a claim, tested at model tier, not a waiver.

## Addendum 2026-11-06b (null-constructor v2 + family-wise subset; owner-go 2026-11-06)
V-1 rerun under a corrected unrelated-concept constructor:
- null-3 v2 = diff-of-means of a contrast from a DIFFERENT behavioral domain
  (format-style contrast: uppercase-vs-lowercase prompt renders, same content),
  with a CONSTRUCTION-TIME ORTHOGONALITY GATE: |cos(null, recovered direction)|
  <= 0.2 per layer, computed and receipted BEFORE any certification; a draw
  failing the gate is re-drawn once with a new seed offset, then recorded
  GATE_EXHAUSTED (the gate failure itself is a row).
- The old null-3 shape is reclassified as its own arm type:
  CONFOUNDED_POSITIVE_CONTROL — expected to sometimes certify; counted
  separately; never in the null floor denominator.
- Family-wise obligation subset (pre-run, stride-2 over certified edits):
  {plant-1, plant-3, plant-5}; floor 0/4 per edit as before; the remaining
  three certified edits carry a named DEFERRED_FAMILY_WISE row, not silence.
- V-2 runs on plant-1 only this arc (ablate/restore/relocate per original
  text); other edits' V-2 = named deferral.
