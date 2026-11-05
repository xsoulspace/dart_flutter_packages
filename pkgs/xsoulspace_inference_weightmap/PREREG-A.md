# PREREG-A — Phase A (frozen 2026-11-05, pre-result)

Arms A1–A4. Decision rules below are FROZEN; changes require a new prereg
row, not an edit. Blinding seed: **20261105**. Battery law: serial `-j 1`.

## A1 · Mechanical edit audit
- Inputs: `Qwen/Qwen3.5-0.8B` (base), `RikiyaT/Qwen3.5-0.8B-weight-space-programming` (edited). Both verified present on HF 2026-11-05; Apache 2.0.
- Expected (from the model card claim): exactly **2** differing tensors — MLP `down_proj` of layers 15 and 19 — and **131,072** differing elements total; card SHA-256 verified if published, else computed digests become the baseline truth (recorded, not assumed).
- PASS: diff matches the claim shape (2 tensors / 131,072 elements) and every other tensor is byte-identical. FAIL: any other tensor differs, or count mismatch → named mismatch class in VERDICTS.md.
- No behavioral claim attaches to A1.

## A2 · Replication eval
- Suites: MATH-500, GSM8K (test), IFEval (verifiable subset), token-limit-hit rate.
- Sampler: **greedy** primary (pre-registered); their harness config, if recoverable from `lm_understand-logs/exp8_math`, reported as secondary, never substituted.
- Thinking/token budget: 32,768 cap (the paper's reported loop cap); max-new-tokens fixed per suite in A4 freeze.
- PASS (calibration C0): base within CI of their reported 7.9% MATH-500 AND edited within CI of 48.1% (CI = Wilson 95% on per-problem correctness; their `eval/` raw scores as secondary comparison). Token-limit rate: base ≈93%, edited ≈31–33%.
- NON-REPLICATE: allowed outcome IF a named cause (sampler/budget/tokenizer/scoring) is identified and recorded; downstream arms blocked until the cause is fixed and A2 re-run. Unnamed non-replication = harness suspect = Phase A kill.

## A3 · V-0 planted ground truth (qwen0.6B mirrors)
- K=8 planted obstacles: rank-1 contrastive-steering directions (repeat/loop
  signature) written into MLP down_proj columns of two mid layers; planted
  vector retained as ground truth (cosine target).
- K=8 null plants: matched-norm random Gaussian directions, same tensors.
- Pipeline blind: arm IDs only; proposer and certifier see no labels.
- Floors (program gate): **specificity ≥ 7/8** null plants yield no certified
  edit; **sensitivity ≥ 6/8** planted obstacles recovered with cosine ≥ 0.9 to
  the planted direction AND behavioral delta in the pre-registered direction
  on G2-shaped cells (loop-rate ↓, task success not ↓ on G0/G1).
- Below either floor: **program halts before any edit claim**; the halt, the
  measured rates, and the denominator are recorded as the verdict.
- Multiplicity: recovery tested once per plant (primary contrast); secondary
  cells (layer choice, rank) Holm-corrected.

## A4 · Eval harness freeze
- Frozen artifacts: `lib/src/scorers.dart`, `tool/eval/*.py` scoring paths,
  sampler config table, per-suite max-new-tokens, G-cell names list. Each
  frozen with sha256 in VERDICTS.md at freeze time.
- Post-freeze change = new prereg row + re-run of affected arms.

## Stop rules
- Phase A kill: unnamed A2 non-replication, or A3 floor miss (halt = verdict).
- Nothing in Phase A authorizes an edit claim on any production cast.
