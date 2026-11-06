# V12 summary — PREREG-C V-1 / V-2 LIVE on A3 plant-1 (arm-002)

Date: 2026-11-06 (UTC). Actor: zcode V12 (session seat, branch ag-c, no commits).
Target edit: the A3-certified removal edit on plant-1 = arm-002
(loop_G2 M→R 0.667→0.333, task 0.045→0.455, mean cosine 0.988; join-table row
`a3-plant-1`). Pre-registration: `receipts/V1-nulls.jsonl` seq 0
(digest `2b39786909c559a925f47c3348e67b189821275860620747c78f43e41bd9b8c1`),
written BEFORE any V12 measurement. Frozen floors: PREREG-C V-1 = **0 of 4
nulls certified**; any certified null = NAMED `NULL_LEAK` → HALT, V-2 not run.

## HEADLINE

**V-1: NULL_LEAK — 1 of 4 nulls certified (floor 0/4 NOT met) → pipeline HALT.
V-2: NOT_RUN (killed by the V-1 halt per PREREG-C and the task gate).**
The halt and its denominator are the verdict. Already-recorded A3 measurements
are untouched (PREREG-C kill-clause scope).

## Instrument continuity (all green, pre-verdict)

- Rebuilt plant-1 mirror byte-identical to A3 arm-002: `mirror_shard_sha256`
  `22e52d07164ca45f379ccb7ddc42e52a39ec719f73e3d043a3551baa931f02e7` matched
  in BOTH batches; 308/308 unedited tensors identical; edits confined to the
  64 planted columns of L15/L19 down_proj at scale 4.8.
- Recovery reproduced exactly: fresh loop+neutral captures on the rebuilt
  mirror + frozen `a3_propose.py` → direction_sha256 L15 `4cb33029…`, L19
  `15de5e61…` — identical to the archived `recovered.json` (diff norms
  10.892481 / 13.957288 identical).
- Frozen certifier continuity: `a3_score.dart` re-run on the archived A3
  work-dir reproduced `receipts/A3/blind-scored.json` IDENTICALLY (all 16
  arms, all rates, all battery digests) before any V12 battery ran
  (`receipts/V12/a3_score_continuity.json`).
- Battery_M determinism: 34/34 cells identical to the archived arm-002
  `battery_M.jsonl` (per-cell output_sha256) AND 34/34 identical across
  batches B1/B2 (two separate mirror rebuilds, ~2.5 h apart). No M_DRIFT,
  no ABULATE/RESTORE flags needed.
- Repair plumbing verified for all 4 nulls: applied direction_sha256 ==
  pre-registered manifest spec, scale −4.8, 64 columns == arm-002 columns,
  tensors == L15/L19 down_proj, `model_on_disk_untouched: true`
  (`receipts/V12/repair_receipt_null{1..4}.json`).

## V-1 per-null results (frozen rule: certified := loop_G2(R) < loop_G2(M) AND task(R) ≥ task(M))

M reference (identical in both batches and vs A3): loop_G2 = 0.667 (8/12),
task = 0.045 (1/22).

| null | construction (seed 20261106, pre-registered) | cos(null, d_hat) L15/L19 | loop_G2 M→R | task M→R | flips | certified |
|---|---|---|---|---|---|---|
| v1-null-1 gaussian | iid N(0,1)×1024, unit-normalized, same 64 cols | −0.043 / +0.031 | 0.667 → **1.000** (+0.333) | 0.045 → 0.091 | 1 | NO |
| v1-null-2 shuffle | seeded within-layer permutation of d_hat (norm preserved) | +0.021 / +0.031 | 0.667 → **1.000** (+0.333) | 0.045 → 0.182 | 5 | NO |
| v1-null-3 unrelated | unit diff-of-means(G0-slugify bank, frozen neutral bank) captured ON the plant mirror, frozen proposer rule | **+0.681 / +0.718** | 0.667 → **0.583** (−0.083) | 0.045 → **0.364** (+0.318) | 7 | **YES → NULL_LEAK** |
| v1-null-4 quantnoise | sign_i · halfULP_bf16(&#124;4.8·d_hat_i&#124;), unit-normalized | −0.185 / −0.184 | 0.667 → **1.000** (+0.333) | 0.045 → 0.136 | 2 | NO |

Family-wise (this edit only; 1 of the 6 A3-certified edits): 1/4 certified,
Wilson 95% CI **[0.046, 0.699]**. Remaining 5 certified edits deferred;
the program-wide rate accumulates only as (if) they run under a new prereg
row after this halt is dispositioned.

## NULL_LEAK diagnostics (recorded, honest)

- Knife edge: a single G2 cell fell off the 256 cap (`g2-b-count60`
  256→195, cap_hit True→False) → loop 8/12 → 7/12. Task side: 7 flips all
  false→true (`g0-ws`, `g1-perm-01..06`) — the same flip pattern family as
  the true removal edit (A3 R had 9 flips incl. these).
- Geometry: the pre-registered "unrelated-concept" pair (G0-slugify vs
  neutral, on the mirror) is NOT directionally unrelated to the recovered
  loop direction: cos ≈ 0.68/0.72. Both are task-vs-neutral contrasts and
  share a task-engagement component; the projection of −4.8·null3 onto the
  plant direction (≈ 0.7 × 4.8 ≈ 3.4 effective removal) partially un-loops
  the mirror. The other three nulls (|cos| ≤ 0.185) all WORSENED loop rate
  (+0.333) and never approached certification.
- INTERPRETATION (labeled; NOT a rule change): the frozen certification rule
  cannot distinguish "removed the recovered direction" from "removed any
  direction with sufficient projection onto it". Whether the remedy is a
  cosine-gated null family, a genuinely non-task contrast pair for null-3,
  or accepting a measured false-positive rate for removal certification, is
  a NEW PREREG-C row — program-owner decision, not runner decision. This
  runner applied the frozen floor as written and halted.

## V-2 (NOT RUN)

Halt row: `receipts/V2-mechanism.jsonl` seq 0 (digest
`1cb5b5712e458af78e2ec198dacbd8a130ee10fd7e1dbb3a83ea24726bb720f7`).
Pre-registered rules (tolerance = half the removal effect = 1/6; EFFECT on
held-out G1 perm cells, threshold +0.25; classes PASS /
EFFECT_TRUE_MECHANISM_FALSE / EFFECT_FALSE) stand unused in seq 0 of
V1-nulls.jsonl; intervention specs (ablate scale 0.0 / restore verbatim
arm-002 repair_spec / relocate both components to L8 down_proj) are built,
digest-recorded (`receipts/V12/nulls_manifest.json`), and preserved for a
future re-preregistered run. B3 was never launched; 0 s of device time spent
on V-2.

## Device / lock / power ledger (protocol v3; serial -j 1; all wall_ms NON-claims)

| batch | content | lock_wait_ms | device wall (steps) | mirror swept |
|---|---|---|---|---|
| B1 | build+gates, loop/neutral/slugify captures, propose, battery_M, null1, null2 | 830 000 (10 s retries) | ~322 s | yes |
| B2 | build+gate, battery_M, null3, null4 | 690 000 | ~264 s | yes |
| B3 | NOT RUN (halt) | 0 | 0 | n/a |

Contention source: A2-local capcurve chunks cycling the same lock (waits are
non-claims; one courtesy request broadcast at 02:41 UTC per protocol v2
precedent). Power: AC, battery 95% charging across all batches. loadavg at
B1: 4.0/16.8/15.7 (heavy external load — wall_ms non-claims per house law).
Every model load under the mkdir lock; rmdir + 3 s courtesy after each batch;
waits receipted (`receipts/V12/B1-receipt.json`, `B2-receipt.json`).

## Files touched (this run)

- NEW helpers (V12-owned, never frozen tools): `tool/runs/v12_nulls.py`,
  `tool/runs/v12_batch.py`, `tool/runs/v12_verdict.py`
- NEW receipts: `receipts/V1-nulls.jsonl` (6 hash-chained rows: run-plan,
  4 nulls, verdict), `receipts/V2-mechanism.jsonl` (1 halt row),
  `receipts/V12/` (this summary, scored outputs, payloads, repair + mirror +
  batch receipts, specs, manifest, slugify-direction proposer output,
  scorer-continuity output), `VERDICTS.md` (+2 rows)
- MODIFIED: none of the frozen tools/oracles (digests verified in run plan;
  `a3_score.dart`, `a3_battery.py`, `a3_propose.py`, `make_mirror.py`,
  `apply_delta.py`, `capture_activations.py`, `cells_frozen_A3.json`,
  `scorers.dart` all run-only)
- Swept on sight: stale `tool/runs/__pycache__` (house law; a prior runner
  forgot PYTHONDONTWRITEBYTECODE)
- Scratch (auto-swept, never repo): `$TMPDIR/wm-v12/` (batteries:
  battery_M_B1 `f55f992b…`, battery_M_B2 `d1bb0b75…`, null1 `9e94ca5e…`,
  null2 `3a422acf…`, null3 `4e41a044…`, null4 `67aadc59…`; captures:
  slugify `31c0055f…`, loop `122c8b06…`, neutral `e671e09b…`;
  recovered_fresh `07c84455…`, recovered_slugify `b8ac36e2…`)

## NAMED issues

1. `NULL_LEAK` (the verdict): v1-null-3 certified; floor 0/4 not met; HALT.
2. Lock starvation pattern re-observed (A2 rapid re-acquire vs 10 s retry):
   resolved by patience, waits receipted; no protocol violation.
3. Stale `__pycache__` in `tool/runs` — swept on sight (house law).
4. Denominator honesty: this V-1 run covers 1 of 6 certified edits; the
   family-wise PREREG-C obligation (all edits) remains open and is recorded
   as deferred-by-halt, not completed.
