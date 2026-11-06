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

Status (arc-2, updated 2026-11-06 ~17:00 local): **PARTIAL — denominators:
glue 2/2 (+1 glue amendment p2_cell.sh LOCK_SLEEP_S); pools 2/2 with BOTH P-2b
legs COMPLETE (gsm8k derived-input leg closed per addendum 2026-11-06b); base
sides 3/3 cells (live digest re-verified arc-2); edited sides 0/4; practice
passes 0/10 complete (pass 1 at 88/128 rows, chunks 00-10); mirrors 0/3;
P-2b delta NOT_REACHED (pool READY, derivation precheck PASSED)** — arc-2 is
in **FLEET_YIELD_V12 HOLD** (coordinator order 16:58 local: device yielded to
V-1v2; zero lock acquisitions until coordinator go; resume pointer = receipts
seq 17: pass 1 next chunk index 11). Arc-2 device wall used ≈1355 s of the 3 h
ceiling (device-batch seconds; lock waits receipted separately as non-claims).
Arc-1 status (battery-bound, 40/128 rows) is superseded but retained in the
chained receipts. Run receipt: `receipts/P2-run.jsonl` (chained rows, seq
0-17). Scratch state (resume authority): `$TMPDIR/p2-artifacts/run/
manifest.jsonl` + per-pass dirs. Absolute ms/tok_s are NON-CLAIMS (POWER.md);
arc-2 runs on **AC power (charging)** — no battery constraint; contention
lock-waits receipted non-claims (sibling A2 32k arm until ~17:0x, then V-1v2).

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
  DISTRIBUTIONAL_CONTAMINATION_NOT_MEASURED carried).
- **GSM8K leg CLOSED arc-2 via the DERIVED-INPUT row** (PREREG-D addendum
  2026-11-06b, owner-go; builder stays FROZEN): raw gsm8k_train.jsonl sha
  `06d0dd56…` == frozen constant → byte-level U+2028/U+2029→SPACE (2× U+2028
  on physical line 2379, id gsm8k_train_2381, inside the `problem` string) →
  derived sha `52ae36c6…` (`p2b-derived/derived_receipt.json` records raw +
  derived digests + exact transformation; raw splitlines 7471 ≠ 7469 rows =
  the NAMED builder refusal, derived splitlines 7469 == rows). Frozen builder
  rc=0 on derived: `p2b_gsm8k_train.jsonl` 7469 rows (passthrough),
  **gsm8k_test overlap removed = 0** vs the FULL 1319-row test set →
  PAPER_DISJOINTNESS_CLAIM_VERIFIED_0_OVERLAP now covers BOTH legs (literal
  level; distributional carried). MATH leg unchanged (`abe7982b` passthrough).
  Arc-1 exclusion UPSTREAM_U2028_GSM8K_TRAIN_BUILDER_INCOMPATIBLE is CLOSED
  (receipt seq 14); arc-1 builder receipt archived at
  `$TMPDIR/p2-artifacts/run/p2b_build_receipt_arc1.json`.

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

**ARC-2 (AC restored): 88/128 rows (11/16 chunks) then FLEET_YIELD_V12 HOLD.**
Chunks 07-10 completed arc-2 (walls 375/309/334/≈337 s; lock waits 1760/440/
310/…s receipted — contention vs the sibling A2 capcurve_edited_32768 arm
running 32k-cap chunks under its own --max-min 100). Contrast at yield:
**80 LOOP hits @1024 / 8 NEUTRAL** (early finishers 508/671/742/748/833/939/
975/996 tok) → neutral rate 9.1%, within-batch contrast VIABLE. First arc-2
resume process died by EXTERNAL SIGTERM 16:26 (source UNKNOWN_NAMED, seq 16;
state unaffected — chunk-skip resume); relaunched detached (nohup+disown).
At 16:58 the coordinator ordered the fleet yield: chunk10 finished +
manifested first, script TERMed between chunks (no orphan generator, lock
free), V-1v2 acquired. **Resume pointer: next chunk index 11 (rows [88,128) =
chunks 11-15), same recorded command, HOLD until coordinator go.**

## NAMED issues this arc

POWER_BATTERY_RUN (arc-1; arc-2 on AC, no battery constraint);
UPSTREAM_U2028_GSM8K_TRAIN_BUILDER_INCOMPATIBLE — **CLOSED arc-2 via the
derived-input row** (addendum 2026-11-06b; receipts seq 14-15);
EXTERNAL_SIGTERM_UNKNOWN_SOURCE (arc-2 16:26 kill of the first resume process;
state unaffected; relaunched detached; seq 16); FLEET_YIELD_V12 (coordinator
hold from 16:58; seq 17); P2_CELL_LOCK_SLEEP_S_UNDEFINED (glue bug in
`$TMPDIR/p2-tools/p2_cell.sh`: referenced-undefined under `set -u` = abort on
any lock contention; fixed to the documented 30×60 s contract, sha
`e63798eb…`, frozen tools untouched; seq 13-14);
BUILDCHECK_BATTERY_STOP (make_mirror leg still unexercised; the pass-1 build
step will exercise it under receipts); CUMULATIVE_MEAN_RENORMALIZED_UNIT;
CROSS_CAST_TRANSFER_ASSUMPTION_S4.8; PRACTICE_RENDER_SAME_AS_A2;
BASE_REUSE_A2_DETERMINISTIC (receipted; arc-2 live re-verification: base score
files digest-match seq 7/8 exactly and the frozen scorer reproduces every
statistic); CAP_4096_VS_32768 + the A2-local comparability caveats
(subset/sampler/template) ride every row;
TEMPLATE_WHITESPACE_COLLAPSE_NOTE: a future end-to-end p2_runner run collapses
whitespace runs in suite `problem` text (build_prompt_file), so runner-driven
prompt bytes may differ from the A2 prompt files by collapsed double spaces —
direct cells here feed the A2 prompt files byte-exact (reuse-valid).

## Verdict

_PENDING — status row (COMPLETE/PARTIAL + denominators + resume pointer) is
appended to VERDICTS.md at arc end; PARTIAL-with-denominator is a verdict._
