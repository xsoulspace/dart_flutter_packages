# A2-LOCAL summary — PREREG-A arm A2 (addendum 2026-11-05 + addendum 3 2026-11-06)

Status: **STOPPED — OWNER STOP ORDER 2026-11-06 16:15Z** (network lag; relayed
by coordinator during the V-1v2 halt-closing hold). Arm verdict class this
arc: **PARTIAL with denominators achieved** (named cause OWNER_STOP_NETWORK_
LAG; addendum law: PARTIAL-with-denominator is a verdict). Exact resume
pointer: run receipt `owner_stop` row — capcurve edited 32768 rows 5-7
(chunk05; rows 0-4 manifested: hits 3/5), relaunch command + launch
accounting + post-completion steps recorded there. Unified rewrite by resume
actor 2; remaining scope per **PREREG-A addendum 3**: capcurve edited 32768
completion (n=8) — everything else below is COMPLETE or COMPUTE_DEFERRED
with resume pointers.
Run receipt: `A2-local-run.jsonl` (append-only). Scratch artifacts:
`$TMPDIR/a2-artifacts/` — digested in the run receipt; absolute ms/tok_s are
NON-CLAIMS (POWER.md), ratios and token counts are measurements.

## Protocol (frozen) and comparability facts

- Generation: `pkgs/xsoulspace_inference_mlx_native/tool/nursery/wm_qwen35_generate.py`,
  mlx-lm 0.32.2 venv, **greedy** (pre-registered primary), thinking-mode chat
  template pre-rendered and one-lined (TEMPLATE_NEWLINES_COLLAPSED, identical
  both configs).
- Checkpoints: base `Qwen/Qwen3.5-0.8B`, edited
  `RikiyaT/Qwen3.5-0.8B-weight-space-programming` (= exp8 **p50c**: 64 MLP
  down_proj columns × layers 15/19, A1-audited). Tokenizer files sha-identical.
- Their harness (recovered, SECONDARY, never substituted): vLLM think35,
  temp 0.6 / top_p 0.95 / top_k 20 / presence_penalty 1.5, 32,768 cap,
  ×4 (MATH) ×2 (GSM8K, IFEval) samples, math-verify on last `\boxed{}`,
  official IFEval checkers post-think.
- Scoring: `tool/runs/a2_score.dart` over FROZEN `lib/src/scorers.dart`
  (14/14 digests re-verified at this resume; cross-check 39/39 green).
- Datasets: MATH-500 (HF rows API), GSM8K (HF rows API — NAMED
  **GSM8K_RAW_GITHUB_404**), IFEval (HF rows API, 541). FETCH-RECEIPT.sha256
  written BEFORE any scoring.
- Device lock v3 + fleet decisions: per-batch mkdir lock, 10s acquisition
  retries (30-min bound), rmdir + 3s courtesy, waits receipted; memory rules
  2026-11-06 (LOAD-AFTER-LOCK — no weights held while waiting: satisfied by
  construction; detached launches + exact-PID bookkeeping; zero pkill/kill
  issued by this actor this arc — kill_statement row). Fleet decision 2
  (~15:32Z): A2 HELD at a clean chunk boundary while V-1v2 (halt-closing arm)
  finishes; priority = halt-closer > comparability.
- Power: predecessor rows AC; successor IFEval rows 44-90 Battery Power
  discharging (BATTERY_POWER_ROWS_44_90; wall non-claims); this resume
  AC-charging from 11%; no battery events this arc. Decode rate varies with
  machine state (~31 tok/s predecessor AC vs ~17-21 tok/s charging-under-load
  this session) — absolute rates NON-CLAIMS; scores/token counts
  power-invariant (greedy determinism, cross-checked).
- Resume law: manifests are authority; completed rows never re-run; stale
  locks recovered only after verified-no-owner rmdir (×2, named); determinism
  cross-checks recorded where a rescoring overlaps a scored prefix.

## NAMED premise gaps

1. **ADDENDUM_IFEVAL_SHORT_OUTPUT_PREMISE_FALSIFIED** (published mean_tokens
   base 25,296 / edited 4,241 @32k contradict "short outputs"; IFEval
   comparability DIRECTIONAL ONLY).
2. **EMPTY_ANSWER_LENIENT_ROWS = 23/91** (frozen scorer passes empty answers
   on exclusion/max-only specs; strict-gated counts reported alongside).
3. **GSM8K_RAW_GITHUB_404** (HF fallback, digest-receipted).
4. **TEMPLATE_NEWLINES_COLLAPSED** (identical both configs).
5. **SAMPLER_DELTA** (greedy ×1 vs temp 0.6 avg@n).
6. **COMPUTE_SUBSTRIDE_32K n=8** (first 8 of 24 stride-21 prompts at 32k).
7. **BATTERY_POWER_ROWS_44_90** + per-chunk power facts (wall non-claims).
8. **CAP_4096_VS_32768_TRUNCATION_SUPPRESSION** (math24/ifeval accuracies
   floor-biased: both configs saturate 4096 while published means are
   22-31k tokens at 32k cap).

## Published targets (Wilson 95% on their denominators)

| cell | base (unedited) | edited (p50c) |
|---|---|---|
| MATH-500 acc @32k, avg@4 | 7.9% [6.80, 9.16] n=2000 | 48.1% [45.92, 50.29] n=2000 |
| GSM8K acc @32k, avg@2 | 13.84% [12.57, 15.21] n=2638 | 67.10% [65.28, 68.86] n=2638 |
| IFEval acc @32k, avg@2 | 20.98% [18.66, 23.51] n=1082 | 62.29% [59.37, 65.13] n=1082 |
| MATH-500 token-limit cut @32k | 93.0% [91.80, 94.04] | 33.05% [31.02, 35.14] |

## Cells

### Cell 1 — IFEval verifiable subset (cap 4096, greedy) — COMPLETE 91/91, NON_REPLICATE

Paired n = **91/91** mappable rows (full pre-registered subset; subset =
91/541, 450 excluded with per-reason counts). Rows 0-43 predecessor (AC),
rows 44-90 successor (battery — wall non-claims).

| config | k/n | score | Wilson 95% | empty | lenient empty passes | strict gated | cap hits @4096 | mean tok |
|---|---|---|---|---|---|---|---|---|
| base   | 39/91 | 42.9% | [33.2, 53.1] | 29 | 11 | 30.8% | 46 (50.5%) | 2277 |
| edited | 38/91 | 41.8% | [32.2, 52.0] | 20 | 8 | 33.0% | 27 (29.7%) | 1576 |
| published base (32k, temp0.6 avg@2, official, full 541) | — | 21.0% | [18.7, 23.5] | — | — | — | cut 74.9% | 25296 |
| published edited (same) | — | 62.3% | [59.4, 65.1] | — | — | — | cut 2.2% | 4241 |

Determinism cross-check: first-44 rescoring reproduces the recorded n44 cells
EXACTLY (both configs). Hit-flag agreement 91/91 both configs.

**Cell verdict: NON_REPLICATE (named causes)** — supersedes the PARTIAL-44
verdict; class unchanged at full subset. No CI contains the other point in
either config. Local paired delta −1.1 pp raw / +2.2 pp strict-gated
(favoring edited), CIs overlap → no significant local delta; published
+41.3 pp not approached. Causes: IFEVAL_SUBSET_COMPOSITION;
GREEDY_VS_SAMPLED_TRUNCATION_REGIME; CAP_4096_VS_32768;
EMPTY_ANSWER_LENIENT_ROWS; SAMPLER_DELTA; TEMPLATE_NEWLINES_COLLAPSED;
BATTERY_POWER_ROWS_44_90 (wall non-claims only). NOT harness-suspect.
IFEval is not part of calibration C0.

### Cell 2 — token-limit cap curve (MATH-500 stride-21; n=24 @4096; n=8 @32768 SUBSTRIDE; 8192 DEFERRED)

Hit rule: frozen `tokenLimitRate` (count ≥ cap); generator-flag agreement
24/24, 24/24, 8/8 on completed runs.

| cap | config | hits/n | rate | Wilson 95% | mean tok | state |
|---|---|---|---|---|---|---|
| 4096 | base | 22/24 | **91.7%** | [74.2, 97.7] | 3843 | COMPLETE (AC) |
| 4096 | edited | 20/24 | **83.3%** | [64.1, 93.3] | 3734 | COMPLETE (AC) |
| 32768 (n=8) | base | 7/8 | **87.5%** | [52.9, 97.8] | 28779 | COMPLETE; published 93.0 [91.8,94.0] INSIDE our CI → base replicates directionally |
| 32768 (n=8) | edited | 3/5 so far (r1,r3,r4 HIT; r0 1801, r2 864 no-hit) | — | — | — | **PARTIAL 5/8 at OWNER STOP 16:15Z** (held since fleet decision 2 15:33Z; resume pointer = run receipt `owner_stop` row: rows 5-7, chunk05, exact relaunch command) |
| 8192 | base | — | — | — | — | COMPUTE_DEFERRED (addendum 3; 0 rows; resume command in `compute_deferred` row) |
| 8192 | edited | — | — | — | — | COMPUTE_DEFERRED (addendum 3; 0 rows) |

@4096 reading: BOTH configs saturate the 4k cap (published edited
mean_tokens 22,037 ≫ 4096) — delta −8.3 pp, CIs overlap; the config contrast
lives at 32k. Events: EXTERNAL_STOP ×2 (reaper pattern → detached launches),
STALE_LOCK_RECOVERY ×2 (verified-no-owner rmdir), LOCK_TIMEOUT ×2 (bounded,
receipted; V6/V-1v2 contention), FLEET_HOLD_2 (coordinator hold at clean
boundary, exact-PID stop of own child).

### Cell 3 — MATH-500 accuracy n=24 stride-21 (cap 4096, greedy) — COMPLETE (addendum-3 cell), PARTIAL

Zero new device time: scored from the digest-verified capcurve 4096 gens
(addendum-3 reuse allowance; the cap-curve prompt set IS the stride-21 n=24).
Frozen `--cell math` mapping (post-think text, last `\boxed{}`, frozen
mathScore). Cross-arm check: P-2's independent reuse of the base gens scored
EXACTLY 4/24 = 16.67% [6.68, 35.85] = this cell's base row.

| config | k/n | acc | Wilson 95% | cap hits @4096 | mean tok | published @32k avg@4 |
|---|---|---|---|---|---|---|
| base   | 4/24 | 16.7% | [6.7, 35.9] | 22/24 | 3843 | 7.9% [6.8, 9.2] — INSIDE our CI |
| edited | 6/24 | 25.0% | [12.0, 44.9] | 20/24 | 3734 | 48.1% [45.9, 50.3] — outside our CI by 1.2pp |

**Cell verdict: PARTIAL** — direction REPLICATED (local +8.3pp edited>base;
published +40.2pp), base side REPLICATE (published point inside our CI),
edited side CI-excluded marginally under a floor-biased regime. Named
causes: CAP_4096_VS_32768_TRUNCATION_SUPPRESSION (both configs truncate;
published edited mean 22,037 tok ≫ 4096 cap); SMALL_N_WIDE_CI (n=24);
SAMPLER_DELTA; TEMPLATE_NEWLINES_COLLAPSED; SUBSET (stride-21 n=24 of 500).
The n=100 stride-5 volume cell is COMPUTE_DEFERRED (addendum 3).

### Cell 4 — GSM8K n=100 even-stride (cap 4096, greedy) — COMPUTE_DEFERRED

Addendum 3: deferred with resume pointer (`compute_deferred` receipt row;
prompts+gold digest-receipted, no rebuild needed). 0 rows generated.

## Verdict

**This arc: PARTIAL with denominators achieved** (owner stop 16:15Z during
the V-1v2 priority hold; named cause OWNER_STOP_NETWORK_LAG). Cell standings
as delivered: IFEval **NON_REPLICATE** (91/91 both configs, named causes,
comparability DIRECTIONAL ONLY per pre-score receipt rows); cap-curve
base@32k **directional REPLICATE** of the published 93.0 cut (pub point
inside our n=8 CI [52.9, 97.8]); math24 **PARTIAL** (direction replicated
+8.3pp edited>base; published base point inside our CI; published edited
point marginally outside, 1.2pp, under CAP_4096 truncation suppression);
cap-curve edited@32k **PARTIAL 5/8** (hits 3/5 — early trend below the base
87.5%, i.e. toward the published direction; NOT scored, no verdict);
capcurve 8192 pair + MATH-100 + GSM8K-100 **COMPUTE_DEFERRED** with exact
resume pointers (addendum 3; never silent drops). The FINAL arm verdict
class lands when edited-32k rows 5-7 complete per the `owner_stop` resume
pointer. Comparability caveat attached to every A2-local verdict per
addendum law: caps/subsets/sampler differ from the paper; P-2/P-2b retain
the full-protocol comparison when compute allows.
