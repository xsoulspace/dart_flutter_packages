# P-2 / P-2b summary — PREREG-D head-to-head (comparability arc, 2026-11-06)

> **COMPARABILITY DATA, NEVER A PASS BAR** (PREREG-D P-2; PROGRAM.md benchmark
> policy + non-claims: parity is never a pass bar). Our pipeline is NOT an
> LLM-proposer pipeline; every row below compares the measured pipeline (or the
> unedited base) against PUBLISHED LLM-proposer numbers.
> Published citation (frozen constant in `tool/runs/p2_runner.py`):
> RikiyaT/lm_understand-logs@main exp8_math/eval/RESULTS_excerpt.md —
> Experiment 6 (Qwen3.5-0.8B, thinking on), prompt-v3 rows p10c/p25c/p50c +
> unedited row; retrieved 2026-11-05.
> Published: unedited MATH-500 7.9 / GSM8K 13.8 / IFEval 21.0; token-limit cut
> @32k base ≈93.0, edited(p50c) 31–33 (33.05). p10c 12.3/25.7/49.0; p25c
> 14.1/25.1/39.9; p50c 48.1/67.1/62.3.

Status: **PARTIAL (arc-1, battery-bound) — denominators: glue 2/2; pools 2/2; base sides 3/3 cells; edited sides 0/4; practice passes 0/10 complete (pass 1 at 40/128 rows); P-2b delta NOT_REACHED (pool READY)** (this file is updated as units complete; the
final version carries the status verdict class with denominators). Run receipt:
`receipts/P2-run.jsonl` (chained rows). Scratch state (resume authority):
`$TMPDIR/p2-artifacts/run/manifest.jsonl` + per-pass dirs. Absolute ms/tok_s are
NON-CLAIMS (POWER.md); this arc additionally runs **on battery**
(POWER_BATTERY_RUN, 27%→ at device start 12:17:32Z) with a live sibling A2 arm
sharing device + electrons — contention lock-waits are receipted non-claims.

## Glue (both NAMED gaps CLOSED; VERDICTS row 2026-11-06)

- `tool/runs/p2_scorer_cli.dart` (SCORER_CLI_MISSING): env-contract wrapper
  (WM_SCORED_INPUT/WM_GOLD/WM_SUITE/WM_OUT_JSON, optional WM_CAP) around the
  FROZEN `lib/src/scorers.dart`; IFEval/think-strip mapping IMPORTED verbatim
  from `a2_score.dart` (cited in-file). Cross-check: EXACT reproduction of A2
  recorded results from live bytes (22/24 hits, mean tok 3843.42, ifeval 24/44,
  11 empty answers; row-level hit agreement 24/24).
- `tool/runs/p2_practice_pass.py` (PRACTICE_CMD_MISSING): per-pass WM_* contract;
  128 pool-order prompts → thinking-template render (A2 convention) → greedy
  continuations cap 1024 in ≤20-min v3-lock batches → within-batch contrast
  (hit cap = LOOP else NEUTRAL; empty either set = NO UPDATE, named) → FROZEN
  capture_activations ×2 banks → FROZEN a3_propose unit diff-of-means →
  cumulative mean over contributing passes (unit-renormalized at spec:
  CUMULATIVE_MEAN_RENORMALIZED_UNIT) → FROZEN apply_delta (down_proj L15/L19,
  64 cols PRE-RUN draw seed 20261105 vs real header [1024,3584], direction =
  −cumulative unit, A3 removal convention) × s∈{2.4,4.8,9.6} all-recorded
  never-select-best (4.8 primary = CROSS_CAST_TRANSFER_ASSUMPTION_S4.8) →
  make_mirror (locked) → `edit_manifest.json`.
- Frozen `p2_runner.py --dry-run` with both glue supplied:
  **real_run_blockers = []** (pool ok, p2b ok, suites 3/3).

## Pools

- P-2 pool (`$TMPDIR/p2-artifacts`): 5/5 files sha256-MATCH the frozen
  constants; line counts == kept constants (7469/7275/714).
- P-2b pool (`p2b-pool/build_receipt.json`): **removed_math500_overlap = 0** —
  the paper's disjointness claim is mechanically CONFIRMED for MATH (full
  500-row subtraction); the P-2 vs P-2b MATH delta therefore measures
  DISTRIBUTIONAL contamination only (builder's
  DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED carried). GSM8K pair
  **NAMED-excluded**: UPSTREAM_U2028_GSM8K_TRAIN_BUILDER_INCOMPATIBLE (paper
  gsm8k_train line 2379 carries 2 literal U+2028 chars inside a JSON string;
  the frozen builder's splitlines() NAMED-refuses; frozen tool NOT edited;
  remedy = derived-input row or builder amendment, owner decision).

## Cells (denominators achieved / planned; base sides reuse A2 gens —
deterministic greedy, digest-verified base weights 04b1c301 == A1, exact
statistical reproduction receipted)

| cell | suite/cap | base (unedited) | edited s=2.4 | edited s=4.8 | edited s=9.6 | published comparator |
|---|---|---|---|---|---|---|
| 1 token-limit | MATH-500 n=24 stride-21 @4096 | **22/24 = 91.67%** [74.15,97.68] mean_tok 3843 | — | _PENDING pass-1 direction_ | — | cut @32k: base 93.0 [91.8,94.0], p50c 33.05 [31.0,35.1] (cap differs; 4096 has NO published counterpart — curve context) |
| 2 accuracy | MATH-500 n=24 @4096 | **4/24 = 16.67%** [6.68,35.85] | — | _PENDING_ | — | unedited 7.9 @32k avg4; p10c 12.3; p50c 48.1 (cap/sampler/subset differ) |
| 3 IFEval | n=50 (first 50 of the 91-row A2 mappable subset) @4096 | **27/50 = 54.0%** [40.40,67.03], 14 empty answers, 21/50 cap hits | — | _PENDING_ | — | unedited 21.0 @32k avg2 official checkers; p10c 49.0; p50c 62.3 — DIRECTIONAL ONLY (A2 NAMED gaps carried) |
| 4 P-2b repeat of cell 1 | n=24 @4096 | (same base) | — | _NOT_REACHED (needs own practice passes; pool READY)_ | — | contamination delta = P-2 − P-2b (data, not a bar) |

Budgets: **10 first** (pass 1 of 10 IN FLIGHT at battery stop); 25/50 =
BUDGET_PARTIAL unless a successor completes them (frozen table; runner refuses
non-subsets).

## Practice pass 1 (variant p2, budget 10, batch rows [0,128) of math_train)

**ARC-1 BATTERY STOP at 40/128 rows (5/16 chunks)** — 35 hits @1024, 5 early
finishers (742/975/671/996/939 tok) → neutral rate 12.5%: the within-batch
contrast is VIABLE (both sets expected non-empty at completion). Per-chunk
device walls 234–341 s; 420 s receipted contention wait (sibling A2 arm);
battery 27%→9% discharging across the arc (POWER_BATTERY_RUN). Chunk rows +
lock waits + power facts: `$TMPDIR/p2-artifacts/run/p2/pass_001/
cont_manifest.jsonl`. Resume = rerun the recorded command (completed chunks
skip; resume pointer in receipts/P2-run.jsonl seq 10).

## NAMED issues this arc

POWER_BATTERY_RUN (device wall battery-bound, not 3h-bound; sibling A2 arm
shares device+electrons); UPSTREAM_U2028_GSM8K_TRAIN_BUILDER_INCOMPATIBLE;
BUILDCHECK_BATTERY_STOP (make_mirror leg unverified this arc; frozen builder
with WS-1/A3 receipt history); CUMULATIVE_MEAN_RENORMALIZED_UNIT;
CROSS_CAST_TRANSFER_ASSUMPTION_S4.8; PRACTICE_RENDER_SAME_AS_A2;
BASE_REUSE_A2_DETERMINISTIC (receipted); CAP_4096_VS_32768 + the A2-local
comparability caveats (subset/sampler/template) ride every row;
TEMPLATE_WHITESPACE_COLLAPSE_NOTE: a future end-to-end p2_runner run collapses
whitespace runs in suite `problem` text (build_prompt_file), so runner-driven
prompt bytes may differ from the A2 prompt files by collapsed double spaces —
direct cells here feed the A2 prompt files byte-exact (reuse-valid).

## Verdict

_PENDING — status row (COMPLETE/PARTIAL + denominators + resume pointer) is
appended to VERDICTS.md at arc end; PARTIAL-with-denominator is a verdict._
