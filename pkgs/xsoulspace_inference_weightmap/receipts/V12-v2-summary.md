# V12-v2 — V-1 rerun under null-constructor v2 + family-wise subset + V-2 (plant-1)

Arc: 2026-11-06 (local ~15:00–18:20 EET). Prereg: PREREG-C + addendum
2026-11-06b (owner-go 2026-11-06). Ledgers: `receipts/V1-v2-nulls.jsonl`
(20 rows, CHAIN_INTACT, final digest c215f913…), `receipts/V2-mechanism.jsonl`
(4 rows: v1 halt row KEPT at seq 0 + seq 1–3 real rows, CHAIN_INTACT, final
digest d1000735…). Durable copies: `receipts/V1v2/`. No commits (per task).

## Headline

- **plant-1 V-1 v2: CLEAN_0_OF_4** (floor met; confounded control certified
  on its SEPARATE denominator, never in the floor) → **V-2 ran: class PASS
  (MECHANISM=PASS, EFFECT=EFFECT_TRUE)**.
- **plant-3 V-1 v2: NULL_LEAK (2/4 certified)** → frozen kill clause:
  **HALT = the verdict**; remaining batches do not run.
- **plant-5: HALTED_AFTER_NULL_LEAK** (P5A was in flight pre-verdict;
  completed, QUARANTINED UNSCORED; P5B never launched; named, not silence).
- Family-wise (subset {plant-1, plant-3, plant-5}): **2/8 nulls certified,
  rate 0.25, Wilson95 [0.071, 0.591]**; plants 4/6/7 = DEFERRED_FAMILY_WISE.

## Orthogonality gate (null3-v2, |cos| ≤ 0.2 per layer, pre-certification)

| edit | draw used | cos L15 | cos L19 | gate | spec sha (16) |
|---|---|---|---|---|---|
| plant-1 (arm-002) | d0 (seed 202611063) | 0.129230 | 0.142332 | PASS | fa266fadaf26868a |
| plant-3 (arm-009) | d0 (seed 202611063) | 0.142880 | 0.015003 | PASS | fb2a58119d1e975e |
| plant-5 (arm-015) | — | — | — | NOT_REACHED (halt) | — |

Constructor: unit(mean(UPPER) − mean(lowercase)) of seeded 64-prompt subsets
of the frozen neutral bank, via FROZEN a3_propose.py on captures taken on
E's rebuilt mirror; one re-draw (d1, seed +7919) pre-captured but never
needed (re-draw only on gate failure); GATE_EXHAUSTED path never triggered.
d1 captures retained in $TMPDIR/wm-v1v2/gen/P{1,3}/ (digests in gate receipts).

## V-1 certification per edit (frozen a3_score.dart; certified := loop_G2(R)
< loop_G2(M) AND task_success(R) ≥ task_success(M); scale −4.8, E's columns)

### plant-1 (arm-002) — CLEAN_0_OF_4 (seq 11, digest 81443515…)

| null | loop M→R (Δ) | task M→R | certified |
|---|---|---|---|
| null1 gaussian (REUSED_V12 0b87f0f1…) | 0.667→1.000 (+0.333) | 0.045→0.091 | false |
| null2 shuffle (REUSED_V12 20be6f5b…) | 0.667→1.000 (+0.333) | 0.045→0.182 | false |
| null3-v2 fmt-contrast (gated, fa266fad…) | 0.667→0.917 (+0.250) | 0.045→0.045 | false |
| null4 quant-noise (REUSED_V12 2a0cbec6…) | 0.667→1.000 (+0.333) | 0.045→0.136 | false |

M continuity: 0/34 differing cells (A vs B vs archived arm-002); repair
plumbing 4/4 OK (columns == arm-002's 64, direction digests match specs,
model-on-disk untouched). Contrast with v1: the leaked null-3 (cos 0.68/0.72)
certified at loop 0.583; the gated v2 replacement (cos 0.13/0.14) does not.

### plant-3 (arm-009) — NULL_LEAK, 2/4 certified (seq 17, digest 06ad38af…)

| null | loop M→R (Δ) | task M→R | certified |
|---|---|---|---|
| null1 gaussian (BUILT_FRESH a2d19e1a…) | 1.000→0.750 (−0.250) | 0.045→0.045 | **TRUE** |
| null2 shuffle (BUILT_FRESH 69fac108…) | 1.000→0.917 (−0.083) | 0.045→0.045 | **TRUE** |
| null3-v2 fmt-contrast (gated, fb2a5811…) | 1.000→0.833 (−0.167) | 0.045→0.000 | false (task floor) |
| null4 quant-noise (BUILT_FRESH 1c9a40d6…) | 1.000→1.000 (+0.000) | 0.045→0.045 | false |

M continuity 0/34 (A/B/archive); plumbing 4/4 OK; mirror+recovery gates
reproduce arm-009 archive exactly (7023b5b2…, b5d03ac0…/9eef5034…).

INTERPRETATION (recorded, not a rule change): the leak mechanism differs
from v1's geometric null-3 leak. The plant-3 mirror is SATURATED (loop_M
12/12 at cap = 1.000; task_M 1/22 at floor = 0.0455), so the frozen rule
"loop strictly down AND task not down" is knife-edge-fragile: any large
perturbation dropping ≥1 G2 cell off the cap while sparing the single
passing task cell certifies. The orthogonality gate did its job (null3-v2
cos 0.143/0.015; it was refused only by the task floor despite loop
−0.167). Any remedy (saturation-aware certification, margins, or accepting
the measured FP rate) requires a NEW prereg row — owner decision.

### plant-5 (arm-015) — HALTED_AFTER_NULL_LEAK (seq 18)

P5A (mirror + continuity gates + M + null1 + null2) was IN FLIGHT when the
plant-3 verdict landed (launched pre-verdict 15:56:20Z; BATCH_COMPLETE
16:02:04Z; gates 3/3 PASS: mirror 5e3d259f…, recovery 5c91f459…/240f7b49…).
Measurements QUARANTINED UNSCORED (battery_M_A 1283922f…, battery_null1
9cd610dd…, battery_null2 02a46491…; receipts in receipts/V1v2/ with
_QUARANTINED suffix). P5B never launched. No process killed (fleet rule 3).

## Confounded positive control (plant-1 only; separate denominator)

Old null-3 shape (G0-slugify-vs-neutral diff-of-means on the plant mirror;
spec REUSED_V12 b939db2f…, digest-verified): **CERTIFIED** — loop
0.667→0.583 (−0.083), task 0.045→0.364 (+0.318). Reproduces the v1-null-3
measurement exactly (scored metrics identical; fresh battery_R 33f42d61… vs
v1 4e41a044…, row digests recorded in the seq-10 row). Expected outcome
class ("may certify"); NEVER counted in the null floor (seq 10, e124b477…).

## V-2 (plant-1 only; gate = V-1 clean on plant-1 → satisfied)

Specs + B3 batch REUSED from V12 VERBATIM (ablate 14fa817b…, restore
65d1f5e0…, relocate 5c921943…; digest-verified). Frozen rules from
receipts/V1-nulls.jsonl seq 0 (E_ref = −1/3, tol = 1/6, EFFECT threshold
|ref_G1|/2 = 0.25 on held-out G1-perm cells).

| intervention | loop M→I (Δ) | rule | holds |
|---|---|---|---|
| ablate (zero delta on claimed L15/L19 64 cols) | 0.667→0.667 (0.0000) | dies: \|Δ\| ≤ 1/6 | ✓ (identity: 0/34 cells differ from session M) |
| restore (repair_spec verbatim) | 0.667→0.333 (−0.3333 = E_ref exact) | returns: loop < M and \|Δ−E_ref\| ≤ 1/6 | ✓ (0/34 drift vs archived arm-002 R battery) |
| relocate (both directions → layer 8) | 0.667→0.583 (−0.0833) | dies: \|Δ\| ≤ 1/6 | ✓ (task 0.045→0.000) |

EFFECT: net G1-perm flips(restore) = +6/12 = **+0.500 ≥ 0.25 →
EFFECT_TRUE** (equals the A3 original; ablate 0, relocate 0).
MECHANISM: **PASS** (all three hold). **Class: PASS** (split verdicts
recorded separately, never merged). Rows: V2-mechanism.jsonl seq 1
(unblock note citing V-1 verdict seq 11), seq 2 (interventions), seq 3
(verdict, digest d1000735…).

## Device / fleet / power accounting

Batches (all BATCH_COMPLETE, all gates PASS, all wall_ms rows
wall_ms_claim=false, mirrors swept per batch, serial −j1 under lock v3):

| batch | lock_wait | device stages | power (start→end) |
|---|---|---|---|
| P1A attempt 1 | 0 (acquired 16:58:05) | killed mid-null1 R (27/34 rows), exit 137 | AC |
| P1A attempt 2 | 0 ms | 9/9, ~5.4 min | AC 86→89% charging |
| P1B | 980,000 ms (behind A2 32k chunk) | 10/10, ~6.3 min | AC 96→97% |
| B3 (V-2) | 0 ms | 5/5, ~4.3 min | AC 98% |
| P3A | 0 ms | 9/9, ~5.4 min | AC 99% |
| P3B | 0 ms | 9/9, ~6.0 min | AC 100% |
| P5A (quarantined) | 0 ms | 9/9, ~5.6 min | AC 100% |

POWER RULE never triggered (AC throughout, charging; per-batch pmset tagged
in receipts). Device total ≈ 33 min + 16.3 min receipted waits (within the
~100 min budget). Fleet: FLEET_YIELD_RECEIVED (P-2 hold, seq 1),
FLEET_YIELD_A2_RECEIVED (seq 4); LOAD-AFTER-LOCK structural in v12_batch
(waiter RSS 0.1% verified); detached launches (start_new_session) from P1B
onward; no actor pkills at any point.

## NAMED issues (all receipted in-ledger)

1. **NULL_LEAK** (plant-3; seq 17) — the verdict; halt + denominator stand.
2. **HALTED_AFTER_NULL_LEAK / HALT_ENFORCED_PLANT5_QUARANTINED** (seq 18).
3. **P1A_ATTEMPT1_KILLED** (seq 2) + **KILL_ATTRIBUTION_MEMORY_PRESSURE_SUSPECT**
   (seq 3; coordinator finding: swap 11.2/12 GB, 277k pageouts, jetsam
   suspect; not a pkill) — quarantined, relaunched clean, nothing scored.
4. **V12_RUNPLAN_DIGEST_TABLE_STALE** (run-plan seq 0): v12's frozen-tool
   table cited uncommitted A3-era bytes for a3_battery.py/a3_lock.py/
   make_mirror.py (ee409d76/0289fa49/1f71892e); tree bytes since commit
   3dec77ac (01:38 UTC, pre-v12) = 7c444278/1ff1b008/271c1f04 — what v12
   actually ran and what this arc ran; empirical A3-reproduction gates
   PASSED per batch on all three arms (mirrors + recovery directions
   bit-identical to archives), which is the operative pin. The other 8
   frozen digests match the v12 table exactly.
5. **V12_NULLS_MANIFEST_DIGEST_STALE** (run-plan seq 0): manifest 91163898…
   vs cited 45d45d40… (regenerated post-run-plan when null3 was added);
   reuse authorized on per-spec digests, 7/7 verified.
6. **LOCK_LIVE_SIBLING_HOLDER** (run-plan seq 0): contention observation;
   no lock ever cleared except this actor's own verified orphan (seq 2).

## Reuse vs rebuild (as required by the task)

REUSED (digest-verified): plant-1 null1/2/4 specs, confounded null3 spec +
recovered_slugify, ablate/restore/relocate specs, B3.json (verbatim),
v12_batch.py / v12_nulls.py / v12_verdict.py (unmodified), all 11 frozen
tools (current tree, gates empirical). BUILT FRESH: plant-3/5 null1/2/4
specs (v12_nulls.py, seed 20261106), all null3-v2 specs (gated builder
v1v2_null3v2.py), fmt banks (SEED3 202611063), arc manifests, batch files
P{1,3,5}{A,B}.

## File index

- Ledger: receipts/V1-v2-nulls.jsonl (seq 0 run-plan f7bf8c69…; 5 P1 rows;
  6 P3 rows; 2 ops notes + 2 fleet notes + 1 kill-attribution note; family
  seq 19) — verify: `dart run tool/runs/a3_ledger.dart` prints CHAIN_INTACT
  on every append; last: rows=20.
- receipts/V2-mechanism.jsonl (halt seq 0 KEPT 1cb5b571…; unblock seq 1
  27072460…; interventions seq 2 53185104…; verdict seq 3 d1000735…).
- receipts/V1v2/: batch receipts (P1A/P1B/B3/P3A/P3B/P5A_QUARANTINED),
  mirror/gate/repair receipts per edit, fmt_banks.json, prep_receipt.json,
  arc manifests, blind-scored outputs (P1/P3/V2), all ledger payloads,
  quarantined P5 receipts.
- $TMPDIR/wm-v1v2/: scratch (batteries, captures incl. unused d1 draws,
  sidecars, scorework, quarantined P1-attempt1 + P5A batteries) —
  auto-swept; digests of record are in the ledgers/receipts above.
