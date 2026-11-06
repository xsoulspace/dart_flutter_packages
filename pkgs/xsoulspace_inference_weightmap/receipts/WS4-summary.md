# WS-4 summary — latent/budget predictor (v2 run 2026-11-06, feature-set v2)

> **PROPOSE_ONLY: WS-4 is an ADVISORY predictor — it NEVER certifies an edit
> (PROGRAM.md propose-only law / pattern exp 0007 / PREREG-E). Metrics here
> change eval COST, never verdicts.**

- Date: 2026-11-06 · branch `ag-c` · PREREG-E WS-4 + **Addendum 2026-11-06**
  (feature-set v2, frozen pre-training; PASS bar UNCHANGED; schema edit
  authorized by the addendum ledger row only)
- Machinery: `tool/runs/ws4_train.py` — amended EXACTLY per the addendum
  (`capture_eigen_gap` optional-absent; scalars/encoding follow the field's
  presence; everything else frozen and byte-identical: PASS bar, arms a–e,
  seed 20261105, family-split law, operating-point rule, venv gate, exit
  codes). Amended sha256
  `3ea6a78fffacf772a171147a4601f351bdfb81b5677657ead289bc6559adfdd3`
  (v1 frozen sha `4b7932b11fcd73615fce6ee89c64750051f5676e458fc766978c8d7b4d7c353f`).
  Test gate: `test/phase_e_p2_test.dart` updated to the
  amended schema (negative case moved to `baseline_loop_rate`; new accept
  case for eigen-gap absence + malformed-present refusal) — **27/27 green**,
  including the venv real-run test.
- Builder: `tool/runs/ws4_denominator.py` (v2: feature-set v2 + promotion
  ledger; sha256
  `2bc71be44db7b8dd68d4a1eedbe289c3882fe74ad2d116d8bfc919fff10fe864`).
- **Verdict class: MEASURED_SMALL_N** (n=20 rows / 12 families caps any
  outcome per the addendum — no generalization claim). Frozen PASS-bar
  result, verbatim from the tool: **FAIL — `NOT_BETTER_THAN_CONTROLS` →
  predictor RETIRED, recorded** (PREREG-E: "no appeal here").

## Run result (v2, REAL run in wm-mlx venv, CPU-only numpy 2.5.4, no
  device/model run)

Denominator: `receipts/WS4-denominator.jsonl` — 20 rows (16 A3 + 4 V-1),
sha256 `c60ab2994510e4be4f855becfe6313577cfecae7781a9299bfc620c7d3699ac8`.
Labels (frozen certification oracle): 7 true (a3-plant-1/3/4/5/6/7 +
v1-null-3 confounded-positive-control) / 13 false.

Split (frozen family-split law, seed 20261105, re-frozen at this re-run):
train 8 rows / holdout 12 rows; holdout families {null-gaussian,
null-unrelated, plant-4, plant-6};
**split_digest = `bb180472a72e6534beef0d033e434f3768c9b1647e472c4862cac13a76457db1`**
— identical to the v1 prospective digest (the split is a function of the
family SET only, and the family set is unchanged; the v1 digest
`bb180472…` stays in history as the v1 prospective split).

Encoding (recorded verbatim in the report): scalars
`[delta_norm, column_count, baseline_loop_rate]` (eigen-gap absent, never
imputed) + multi-hot layers {15,19} → dim 5. **Train std = 0.0 on every
dimension** → all dims centered-only per the frozen rule → all-zero feature
matrix: NAMED observation **FEATURE_ZERO_VARIANCE** — the v2 features are
constant across all 20 rows BY A3 CONSTRUCTION (matched-control draws: same
|scale| 4.8 → delta_norm 54.305801 for every row, 64 columns, layers {15,19},
one common band-set of 24 pairs, common baseline 5/12). The denominator
carries no v2-feature signal to learn; every arm necessarily scores constant.

### Per-arm metrics (holdout: 12 rows, 3 positives / 9 negatives, non-degenerate)

| arm | name | threshold (train-chosen) | holdout AUC | holdout FNR @ op | evals skipped | false negatives | skipped/FN | notes |
|---|---|---|---|---|---|---|---|---|
| a | logistic regression (6 params) | 0.500000 | **0.5** | **0.0** | 0 | 0 | null (FN=0) | constant scores (zero-variance features) |
| b | matched-param MLP (h=1, 8 params, residual +2 recorded) | 0.500000 | 0.5 | 0.0 | 0 | 0 | null | not in PASS-bar comparison per PREREG-E (controls are c–e) |
| c | null (train base rate 0.5) | 0.500000 | 0.5 | 0.0 | 0 | 0 | null | control |
| d | exact memo (family key) | 1.000000 | 0.5 | **1.0** | 12 | 3 | **4.0** | 0 memo hits / 12 misses (holdout families unseen by construction = pre-registered memorization floor) |
| e | n-gram table (24 uni / 276 bigram keys) | 0.500000 | 0.5 | 0.0 | 0 | 0 | null | control |

Economics reported raw (PREREG-E): arms a/b/c/e skip 0 full evals at their
operating points (no cost saving); arm d skips 12 evals at the price of 3
false negatives (4.0 skipped/FN) with holdout FNR 1.0 — above the 10% floor
on its own. No arm produces a usable screen on this denominator.

### PASS bar (verbatim, frozen rule)

Rule as recorded in the report: *"FROZEN (PREREG-E): arm (a) holdout FNR at
its operating point <= 0.10 AND arm (a) holdout AUC > max AUC of (c),(d),(e);
FAIL = predictor retired, recorded"*

- constraint: fnr_floor 0.10, arm_a_holdout_fnr 0.0 → **satisfied: true**
- comparison: arm_a_holdout_auc 0.5 vs control_aucs {c_null: 0.5,
  d_exact_memo: 0.5, e_ngram_table: 0.5}; best_control_arm c_null;
  arm_a_beats_best_control → **false**
- **verdict: FAIL · fail_reason: NOT_BETTER_THAN_CONTROLS · on_fail:
  "predictor RETIRED, recorded (PREREG-E); no appeal here"**

Tool stdout (verbatim):

```
{
  "tool": "ws4_train.py",
  "report": ".../receipts/WS4-report.json",
  "pass_bar_verdict": "FAIL",
  "fail_reason": "NOT_BETTER_THAN_CONTROLS",
  "propose_only": true
}
```

INTERPRETATION (recorded, not a rule change): the FAIL is a property of a
zero-variance v2 feature set on a 20-row matched-control denominator —
arm (a) could not differ from the controls because no feature differs
across rows. It retires the predictor per the frozen bar as written;
it is not evidence about latent/budget prediction on a denominator with
feature variance. Reopen routes (owner decision, new prereg row): the
deferred capture_eigen_gap behind the instrument-change row, and/or a
denominator with varying scale/column-count/layer draws (V-3 replication
arms were designed to supply exactly that variance).

## Denominator accounting (v2 assembly)

| source | candidates | strict rows | excluded rows | reason (NAMED) |
|---|---|---|---|---|
| A3 | 16 | 16 | 0 | — (v1 FEATURE_MISSING ×16 **PROMOTED** per addendum) |
| V-1 | 4 | 4 | 0 | — (v1 FEATURE_MISSING ×4 **PROMOTED** per addendum) |
| WS-3 | 48 per-layer priors | 0 | 48 | `NOT_AN_EDIT_ATTEMPT` |
| V-3 | 0 | 0 | 1 ledger entry | `V3_NOT_RUN` (named absence, not zero rows) |
| **total** | **20 edit attempts** | **20 trainable** | **50 ledger rows** | promoted: **20** |

Exclusion sidecar `receipts/WS4-denominator-exclusions.jsonl` (50 rows, sha
`fe2b1b0e…39e2`): 48 NOT_AN_EDIT_ATTEMPT + 1 V3_NOT_RUN + 1 PROMOTED ledger
entry (`promotion-feature-v2-2026-11-06`, promoted_count 20). Integrity
checks all green again at v2 (32/32 A3 spec digests, 4/4 V-1 spec digests,
16/16 certified-agreement join-table vs blind-scored, matched-control column
equalities, unit-norm directions; baseline_loop_rate 5/12 = 0.4166666666666667
from the archived base battery sha `db87f5a3…`).

## MEASURED_SMALL_N caveat (restated per addendum)

n = 20 attempts / 12 families (train 8 / holdout 12, holdout positives 3).
Per the PREREG-E Addendum 2026-11-06 this caps ANY outcome at
**MEASURED_SMALL_N**: the PASS bar was evaluated and printed FAIL by the
frozen machinery, the retirement is recorded as written, and **no
generalization claim exists in either direction** from this denominator.
AUC 0.5 on 3 positives has a Wilson-scale uncertainty that swamps any
ranking claim; economics numbers are raw counts, not rates with power.

## Files (v2)

- `receipts/WS4-denominator.jsonl` — 20 strict rows (tool input), sha `c60ab299…`
- `receipts/WS4-denominator-exclusions.jsonl` — 50 ledger rows, sha `fe2b1b0e…`
- `receipts/WS4-denominator-assembly.json` — v2 builder assembly report
- `receipts/WS4-report.json` — **ws4-report/v1 written by the frozen tool
  itself** (verbatim tool output; pass_bar block above)
- `receipts/WS4-summary.md` — this file
- History preserved: `receipts/WS4-report-v1.json` (v1 refusal wrapper),
  `receipts/WS4-denominator-exclusions-v1.jsonl` (69 rows incl. the 20
  FEATURE_MISSING), `receipts/WS4-denominator-assembly-v1.json`
- VERDICTS.md — v1 row (train / DENOMINATOR_EMPTY_FEATURE_MISSING) kept as
  history; one v2 row appended (append-only ledger law)

---

# v1 history (2026-11-06, feature-set v1) — kept verbatim in condensed form

v1 assembly found all 20 edit-attempt candidates lacking the then-required
`capture_eigen_gap` (A4-frozen capture instrument records per-layer MEANS
only; 78-file receipt sweep, 0 eigen hits; not computable offline) →
excluded NAMED FEATURE_MISSING; strict denominator 0 rows (sha `e3b0c442…`
empty); frozen `ws4_train.py` (unmodified, sha `4b7932b1…`) refused verbatim
exit 1 dry+real: `DENOMINATOR_EMPTY: receipts/WS4-denominator.jsonl has no
non-blank lines` (refusal precedes the venv gate — no numpy, no device).
Arms a–e NOT_TRAINED; PASS bar NOT_EVALUATED; verdict class
DENOMINATOR_EMPTY_FEATURE_MISSING (MEASURED_SMALL_N inapplicable at n=0).
Prospective v1 split digest `bb180472…` cross-validated exact against the
frozen tool dry-run via a scratch-only schema self-test (placeholder
eigen-gap 0.0, never promoted, nothing trained). Remedy route named:
capture-instrument spectra + new prereg row → landed as the PREREG-E
Addendum 2026-11-06 (feature-set v2, eigen-gap deferred not imputed).
Full v1 detail: `receipts/WS4-report-v1.json`,
`receipts/WS4-denominator-assembly-v1.json`,
`receipts/WS4-denominator-exclusions-v1.jsonl`.
