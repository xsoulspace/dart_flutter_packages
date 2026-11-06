# PREREG-D — Phase D (frozen 2026-11-05, pre-result)

Arms V-3, WS-3, P-2/P-2b, P-3, P-4. Floors FROZEN.

## V-3 · Cross-cast × cross-proposer replication
- Casts: qwen3-0.6b-bf16 (primary); second cast chosen by pre-check: loop-rate
  baseline on G2-shaped cells ≥ pre-registered threshold → lfm25-1.2b, else
  qwen3-1.7b-4bit; a cast failing the pre-check is recorded
  `CAST_NOT_LOOPING` (a verdict, not a defect) and substituted.
- Proposers: diff-of-means (primary), masked-attribution prior (WS-3), and a
  random-proposer CONTROL that must certify nothing.
- Agreement: cosine ≥ 0.7 between independent proposer directions on the same
  mirror + certification concordance. Replication PASS = ≥2 casts certify the
  same-concept edit with concordant mechanism (V-2 style, abbreviated).
- Random control certifies anything = NAMED `CONTROL_LEAK` → halt.

## WS-3 · Masked-component attribution prior
Mask each of the 24 text-tower layers' MLP output in turn at capture time;
predict the masked representation from the remaining layers with ridge
regression trained on neutral prompts only; prior score = prediction-error
delta on loop prompts vs neutral.
- k=3 pre-registered. PASS = the layer carrying the planted/recovered
  direction ranks in top-3 above chance (chance 3/24; binomial, family-wise
  across arms p<0.05). FAIL recorded as a verdict on the prior's backbone.
- The prior NEVER certifies (propose-only law); it only ranks candidates.

## P-2 / P-2b · Head-to-head with the paper's protocol
- Same base (Qwen3.5-0.8B), same suites (MATH-500, GSM8K test, IFEval subset),
  same forward-pass budgets {10, 25, 50} as paper exp8; our pipeline is NOT an
  LLM-proposer pipeline, so P-2 compares measured-pipeline vs published
  LLM-proposer numbers: comparability data, never a pass bar.
- P-2b hygiene variant: practice pool strictly disjoint from evals (MATH train
  minus MATH-500 by construction; GSM8K train vs test). The delta between P-2
  and P-2b MEASURES the paper's contamination risk; both recorded.
- Sampler/budget table frozen in A4; token cap 32,768.

## P-3 · Localization benches from released artifacts
- exp1: four tiny game policies (.npz, 140 KB each) + eval/answer_key.json =
  published ground truth. Pre-registered reader features: input-layer spatial
  mass centroid + output-layer action bias; score = label match vs key
  (chance 1/4 per net). exp2 likewise if present with keys.
- exp3: corpus rebuilt from the manifest (digest-checked); induction-head
  detector = QK composition signature; ground truth = analytically computed
  copying/induction heads; score precision/recall @k=4 vs the heads named in
  their run logs.
- Manifest digest drift → exp3 downgrades to qualitative with NAMED reason.

## P-4 · Write-from-scratch (deprioritized)
Runs only if P-3 PASSes and session compute remains; otherwise recorded
`DEPRIORITIZED` with this row as the reason. Kill cheap, no appeal.

## Addendum 2026-11-06 (WS-3 live pass criterion, frozen pre-run)
Planted directions live in TWO layers (15 and 19). WS-3 live PASS criterion:
for a plant mirror, **at least one** planted layer ranks in the prior's top-3
(chance 3/24 per mirror); the base (unplanted) mirror is a control whose top-3
is recorded but not scored. Family-wise binomial across the mirrors actually
run (plant-1 first; extension to more mirrors pre-registered per run row,
never post hoc). Live scope this arc: plant-1 mirror + base control; further
mirrors only under a new row.
