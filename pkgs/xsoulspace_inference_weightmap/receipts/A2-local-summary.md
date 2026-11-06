# A2-LOCAL summary — PREREG-A arm A2 (addendum 2026-11-05)

Status: **IN PROGRESS** (this file is updated as cells complete; the final
version carries the verdict class). Run receipt: `A2-local-run.jsonl`
(harness params + published targets + per-cell rows). Scratch artifacts
(generations, manifests, scores): `$TMPDIR/a2-artifacts/` — digested in the
run receipt; absolute ms/tok_s are NON-CLAIMS (POWER.md), ratios are
measurements.

## Protocol (frozen) and recovered comparability facts

- Generation: `pkgs/xsoulspace_inference_mlx_native/tool/nursery/wm_qwen35_generate.py`,
  mlx-lm 0.32.2 venv, **greedy** (pre-registered primary), thinking-mode chat
  template (`enable_thinking=True`) pre-rendered and one-lined
  (TEMPLATE_NEWLINES_COLLAPSED — the frozen script's line-based prompts-file
  protocol; identical for both configs).
- Checkpoints: base `Qwen/Qwen3.5-0.8B`, edited
  `RikiyaT/Qwen3.5-0.8B-weight-space-programming` (= exp8 **p50c** edit:
  64 MLP down_proj output columns × layers 15/19 — shape confirmed by the A1
  audit row in VERDICTS.md). Tokenizer files sha256-identical.
- Their harness (recovered from `lm_understand-logs/exp8_math`; SECONDARY,
  never substituted): vLLM think35 — temp 0.6, top_p 0.95, top_k 20,
  presence_penalty 1.5, 32,768 cap, samples ×4 (MATH-500) ×2 (GSM8K, IFEval),
  math-verify grading on the last `\boxed{}`, IFEval official checkers on the
  post-`</tool_response>` answer.
- Scoring: `tool/runs/a2_score.dart` over FROZEN `lib/src/scorers.dart`
  (sha256 in run receipt; never edited); cross-check `test/a2_score_test.dart`
  39/39 green (27 hand-scored rows). Scoring-input mapping mirrors exp8
  (math/gsm8k: text after last think-close; ifeval: post-think answer, empty
  when the marker is missing under thinking-on).
- Datasets: MATH-500 (HF rows API, 500), GSM8K (HF rows API openai/gsm8k
  main/test 1319 — NAMED GAP **GSM8K_RAW_GITHUB_404**: both raw-github URLs
  404'd, repo Not Found via API; same upstream OpenAI data), IFEval (HF rows
  API google/IFEval train, 541). Digest receipt: `FETCH-RECEIPT.sha256`
  (sha256 in run receipt) written BEFORE any scoring.
- Compute adaptation (addendum): COMPUTE_SUBSTRIDE_32K n=8 (first 8 of the
  24 cap-curve prompts at cap 32768; recorded in the run receipt, not the
  PREREG file). IFEval cap = **4096** (CHOICE — addendum left it unspecified;
  see premise gap below). Budgeted clean stops between chunks; PARTIAL with
  denominator achieved is a verdict (addendum).
- Device lock (coordinator protocol 2026-11-05): mkdir-lock held per
  (cell,config) run, rmdir on completion incl. TERM/INT traps; waits bounded
  30×60 s and recorded; contention-tagged rows would carry non-claim wall_ms
  (none so far: lock_wait_s=0 on every run).
- Power: AC throughout so far; ioreg Amperage recorded per chunk (0–34 mA —
  the POWER.md charge-current hole: "AC" on a possibly weak brick; absolute
  perf numbers non-claims).

## NAMED premise gaps (recorded before results)

1. **ADDENDUM_IFEVAL_SHORT_OUTPUT_PREMISE_FALSIFIED** — the addendum's
   "IFEval … short outputs; feasible" is contradicted by the published
   mean_tokens at 32k cap (base 25,296 / edited 4,241; cut_share base 0.749).
   At our 4096 cap the BASE IFEval cell is truncation-prone; comparability to
   published 21.0 / 62.3 is DIRECTIONAL ONLY. (Greedy decoding does shorten
   many rows vs their temp-0.6 sampling — measured, see cells below.)
2. **EMPTY_ANSWER_LENIENT_ROWS = 23/91** — frozen `ifevalScore` passes an
   EMPTY answer for spec sets that are exclusion/max-only (19 kw_exclude-only
   rows + word_count-max-only + combos = 23 of 91); exp8 gates every
   instruction on `bool(resp)`. `empty_answer_rows` is counted in every
   IFEval summary so the artifact is never silently folded into the score.
3. **GSM8K_RAW_GITHUB_404** — task-frozen raw URL and canonical repo path both
   404 (repo Not Found 2026-11-05); HF datasets-server fallback used,
   digest-receipted.
4. **TEMPLATE_NEWLINES_COLLAPSED** — the frozen generator's line-based prompt
   file forces newline→space collapse of the rendered chat template; applied
   identically to both configs (paired comparison sound; absolute
   comparability to their byte-exact rendering weakened).
5. **Sampler delta** — ours greedy ×1 sample vs theirs temp 0.6 avg@n; CI
   widths and point estimates are not directly comparable (recorded with
   every verdict, addendum law).

## IFEval mapping (91/541 mappable; 450 excluded with per-reason counts)

| IFEval instruction | frozen spec | caveat |
|---|---|---|
| length_constraints:number_words (at least N) | word_count min=N | whitespace-split word count |
| length_constraints:number_words (less than N) | word_count max=N-1 | whitespace-split word count |
| keywords:existence | kw_include | case-insensitive substring |
| keywords:frequency (at least 1) | kw_include | existence equivalence |
| keywords:frequency (other) | UNMAPPABLE → excluded | |
| keywords:forbidden_words | kw_exclude | case-insensitive substring |
| detectable_format:json_format | json_only | frozen stricter (no fence strip) |
| detectable_format:number_bullet_lists (N) | bullet_list min_items=N | frozen stricter (every non-empty line must be an item) |
| detectable_format:title | upper_title | frozen drops the official <<TITLE>> wrapper rule |
| all other ids (change_case, combination, startend, punctuation:no_comma, language, letter_frequency, highlighted_sections, multiple_sections, constrained_response, rephrase, placeholders, postscript, sentences/paragraphs/nth-paragraph) | UNMAPPABLE → row excluded | counts in run receipt |

Full table + per-row decisions: `prompts/ifeval_mapping.json` (sha256 in run
receipt). Mappable-subset composition: kw_exclude 28, number_words 20,
json_format 17, bullet_lists 15, title 15, existence 12, frequency(1) 2.

## Published targets (Wilson 95% on their denominators)

| cell | base (unedited) | edited (p50c) |
|---|---|---|
| MATH-500 acc @32k, avg@4 | 7.9% [6.80, 9.16] n=2000 | 48.1% [45.92, 50.29] n=2000 |
| GSM8K acc @32k, avg@2 | 13.84% [12.57, 15.21] n=2638 | 67.10% [65.28, 68.86] n=2638 |
| IFEval acc @32k, avg@2 | 20.98% [18.66, 23.51] n=1082 | 62.29% [59.37, 65.13] n=1082 |
| MATH-500 token-limit cut @32k | 93.0% [91.80, 94.04] | 33.05% [31.02, 35.14] |

Task citation "31–33%" = p50c cut_share 0.3305. Our comparable point is the
32768-cap curve cell (n=8 sub-stride); 4096/8192 caps have NO published
counterpart (curve context only).

## Cells

(RESULTS_SLOTS — filled as cells complete; every row: cell, config, n
achieved/denominator, score, Wilson 95%, cap-hit stats, wall, power, locks.)

### Cell 1 — IFEval verifiable subset (cap 4096, greedy)

Paired n = **44 of 91** mappable rows (base budget_stop at 44/91; edited run
matched to 44 → full pair; subset itself = 91/541, 450 excluded with
per-reason counts). Device: per-batch locking; A3 interleave absorbed
(base lock_wait 420 s; edited 2,340 s incl. one named LOCK_TIMEOUT 1,800 s);
power AC throughout, Amperage −257…+71 mA (charge-current hole recorded).

| config | k/n | score | Wilson 95% | empty answers | lenient empty passes | strict gated | cap hits @4096 | mean tok |
|---|---|---|---|---|---|---|---|---|
| base   | 24/44 | 54.5% | [40.1, 68.3] | 11 | 6 | 40.9% | 18 (40.9%) | 1907 |
| edited | 21/44 | 47.7% | [33.8, 62.1] | 8 | 5 | 36.4% | 11 (25.0%) | 1428 |
| published base (32k, temp0.6 avg@2, official checkers, full 541) | — | 21.0% | [18.7, 23.5] | — | — | — | cut 74.9% | 25296 |
| published edited (same) | — | 62.3% | [59.4, 65.1] | — | — | — | cut 2.2% | 4241 |

**Cell verdict: NON_REPLICATE (named causes)** — direction is reversed
locally (base ≥ edited) and no CI contains the other point. Named causes
(all pre-registered as comparability caveats before scoring):
IFEVAL_SUBSET_COMPOSITION (91-row mappable subset, kw_exclude-heavy, frozen
strict checkers vs official full-set checkers); GREEDY_VS_SAMPLED_
TRUNCATION_REGIME (greedy base completes answers — median 655 tok, 41%
truncation @4k — while published base 21.0 is truncation-dominated at 74.9%
cut @32k); CAP_4096_VS_32768 (edited published cut 2.2% vs local 25%);
EMPTY_ANSWER_LENIENT_ROWS (frozen scorer passes empty answers on
exclusion/max-only specs: base 6, edited 5; strict counts shown);
SAMPLER_DELTA (greedy ×1 vs temp 0.6 avg@2); TEMPLATE_NEWLINES_COLLAPSED.
NOT harness-suspect: scorer cross-check 39/39, package 266/266 green,
hit-flag agreement 88/88, outputs coherent. Local same-regime delta
(base−edited): −6.8 pp raw / −4.5 pp strict, CIs overlap → no significant
local effect on this subset. IFEval is NOT part of calibration C0; the
overall-arm verdict waits on the decisive cap-curve and MATH cells.
PARTIAL denominator: 44/91 (of a 91/541 subset).

### Cell 2 — token-limit cap curve (MATH-500 n=24 @4096/@8192; n=8 @32768 COMPUTE_SUBSTRIDE_32K)

Frozen cap-curve prompts: MATH-500 idx=21·i (i=0..23); 32k sub-stride = first
8 of the 24 (addendum-2 COMPUTE_SUBSTRIDE_32K n=8, recorded in run receipt).
Within-cell cap order 4096 → 32768 → 8192 (ordering_decision row: the 32k
point is the only published-comparable one; cap order inside the cell is not
frozen). Hit rule: frozen `tokenLimitRate` (count ≥ cap); generator-flag
agreement 48/48 so far.

| cap | config | hits/n | rate | Wilson 95% | mean tok | power |
|---|---|---|---|---|---|---|
| 4096 | base | 22/24 | **91.7%** | [74.2, 97.7] | 3843 | AC, 0…+71 mA |
| 4096 | edited | 20/24 | **83.3%** | [64.1, 93.3] | 3734 | AC, 0…+57 mA |
| 32768 (n=8) | base | _RUNNING_ | | | | |
| 32768 (n=8) | edited | _PENDING_ | | | | |
| 8192 | base | _PENDING_ | | | | |
| 8192 | edited | _PENDING_ | | | | |

@4096 reading: BOTH configs saturate the 4k cap (published edited mean_tokens
22,037 ≫ 4096) — delta −8.3 pp, CIs overlap; the config contrast is expected
at 32k (published: base 93.0 [91.8, 94.0] → edited 33.05 [31.0, 35.1]).
Events: base@4096 run suffered an EXTERNAL_STOP at row 22 with a stale-lock
leak (trap killed with the process group); recovered by verified manual rmdir
(lock_event rows in run receipt + manifest); relaunched run completed 24/24.

### Cell 3 — MATH-500 accuracy n=100 stride-5 (cap 4096, greedy)
_PENDING_

### Cell 4 — GSM8K n=100 even-stride (cap 4096, greedy)
_PENDING_

## Verdict

_PENDING — verdict class (REPLICATE / PARTIAL / NON_REPLICATE) with named
causes and the addendum's comparability caveat attached to every A2-local
verdict._
