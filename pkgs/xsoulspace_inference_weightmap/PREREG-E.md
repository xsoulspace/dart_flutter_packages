# PREREG-E — Phase E (frozen 2026-11-05, pre-result)

Arms WS-4, V-5, V-6. Floors FROZEN. Propose-only law governs all of Phase E:
no screener, predictor, or prior ever certifies an edit.

## WS-4 · Latent/budget predictor (contract shape from pattern exp 0007)
- Features: delta norm, column count, layer ids, baseline loop-rate, capture
  eigen-gap. Label: battery pass/fail from the A3+V-1+V-3 denominator.
- Arms: (a) logistic regression; (b) matched-parameter MLP; (c) null;
  (d) exact memo (same plant family seen before); (e) n-gram table over
  (layer, column-band) co-occurrence. Train on train-family plants only;
  holdout families never trained on.
- PASS bar: (a) beats best of (c)–(e) on holdout at ≤10% false-negative rate
  at its operating point; economics reported raw (full evals skipped per
  false negative). FAIL = predictor retired, recorded.

## V-5 · Advisory calibration audit
- Screener = WS-4 predictor + WS-3 prior, run over ≥30 sampled candidate edits
  drawn from the recorded denominator (A3+V-1+V-3 attempts, plants and nulls).
- Report ROC + operating point + economics vs full battery.
- Floor: false-negative rate ≤10% at the operating point; else screener
  DISABLED with NAMED `SCREENER_UNCALIBRATED` (disablement is the verdict).

## V-6 · Drift re-certification matrix
- Axes: quant {bf16, 4bit-requant of the edited mirror} × template {chat, raw}
  × sampler {greedy, t=0.6} × engine {rust, python-mlx-lm}.
- Key law: any key-field change ⇒ re-run the pre-registered 3-cell subset;
  verdict stable within tolerance across the matrix = PASS; else
  `DRIFT_<field>_<cell>` named per divergence.
- Engine axis runs only after the Rust qwen3_5 parity digest matches Python
  (parity-pending at freeze time; if parity never lands, the engine axis is
  recorded `PARITY_PENDING`, matrix runs on the Python axis alone).

## Kill clauses
SCREENER_UNCALIBRATED disables WS-4/V-5 tier only; V-6 drift names do not
invalidate the bf16/greedy/python certifications already ledgered (they stay
keyed to their receipts).
