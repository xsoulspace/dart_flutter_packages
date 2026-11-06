# V-6 Drift Re-Certification Matrix — Unified Summary

Arm: V-6 (PREREG-E, frozen 2026-11-05) — drift re-certification of the A3
plant-1 certified edit (arm-002) across key-field changes.
Cast: mlx-community/Qwen3-0.6B-bf16 snapshot 42096995f6402fde107068cf530136fe64b604f8.
Mirror: R removal mirror (plant_1_removal), rebuilt from A3 arm-002 sidecars by
the predecessor (Batch A, verify_rebuild.py 21/21 OK, removal shard
fadd55fa38e846d8f1192551e28637c82a843f4fdae26ddfacf78d7df1402953); 4bit-requant
variant 1e420e6933b30c2e2ed36ab8f95eb078bedf61b13048f6dae629b98a8890be7a
(group_size 64, bits 4, affine; mlx_lm defaults = mlx-community 4bit convention).
Receipt chain: receipts/V6-matrix.jsonl seq 0-27 (hash-chained; seq 0-8 +
predecessor batches A/B; seq 9-27 resume run, batches C/D/E + certify).

Registered tolerance (seq 0, PRE-RUN, not refit): abs 0.084, rel 0 —
ws2 edge-INCLUSIVE law |a-e| <= max(abs, rel*max(|a|,|e|)); ~= 1 cell in 12 per
loop-rate (1/12 = 0.0833 <= 0.084; 2 cells = 0.1667 > 0.084). Token-identity 0
is NOT required for V-6. Reference verdict for ALL subset cells: the single
recorded certification value (A3 arm-002 loop_rate_R = 0.3333333333333333,
PASS) — the frozen 3-cell subset spans key changes by design (semantics
registered pre-run, seq 0 reference_verdicts).
Verdict rule (pre-run): PASS iff score < LOOP_RATE_M_RECORDED 0.6666666666666666;
STABLE iff verdict == reference verdict AND |score - ref| <= tolerance; else
DRIFT_<FIELD>_<cell>. V6_TASK_LEG_NOT_RUN: the task-success leg is not
re-evaluated under key changes (named scope limit).

## Per-axis results (5 pre-registered certification comparisons)

| axis | invocation / leg | cell (comparison) | reference | measured | delta | verdict |
|---|---|---|---|---|---|---|
| (reference) | Q cell1 | bf16__chat__greedy__python-mlx-lm | PASS 0.3333 (recorded A3 arm-002) | PASS 0.3333 (4/12 G2 cap-hits) | 0.0 | STABLE (exact greedy reproduction on rebuilt mirror) |
| quant (4bit-requant) | Q cell2 | 4bit-requant__chat__greedy__python-mlx-lm | PASS 0.3333 | PASS 0.25 (3/12) | 0.0833 <= 0.084 | STABLE (1 cell below ref, tolerance edge inclusive) |
| template (raw) | T cell1-on-raw | bf16__chat__greedy__python-mlx-lm on RAW battery (prompts_raw 3f842a9a) | PASS 0.3333 | FAIL 1.0 (12/12) | 0.6667 > 0.084 | DRIFT_BATTERY_DIGEST_bf16__chat__greedy__python-mlx-lm |
| sampler (t=0.6) | S cell3 | bf16__chat__t=0.6__python-mlx-lm | PASS 0.3333 | PASS 0.4167 (5/12, seed 0) | 0.0833 <= 0.084 | STABLE (1 cell above ref) |
| engine (rust) | E live leg + frozen certify | bf16__chat__greedy__rust vs __python-mlx-lm, loop_rate_G2 bundle | py 0.3333 | rust 0.3333 | 0.0 | STABLE (cross_engine.dart certify AGREE; no DRIFT_ENGINE_REV) |

Matrix verdicts per invocation: Q = STABLE_PASS (drift_names []); T = DRIFT
(3 names, below); S = STABLE_PASS (drift_names []).

## Template axis — the drift finding (all 3 subset cells diverged)

T invocation (key drift BATTERY_DIGEST via the pre-run NAMED
TEMPLATE_VIA_BATTERY_DIGEST wiring; RAW_SURFACE_DEFINITION = chat wrapper AND
' /no_think' removed together; frozen cell ids keep the 'chat' label — the
battery actually served is the raw rendering, evidenced by batch-meta
prompts_file_sha256 3f842a9a6442e0229bbd9ecd8abb829b145aa06c55201b833a9035eed2c0a220):

| cell (frozen id) | ref | measured | stability | drift name |
|---|---|---|---|---|
| bf16__chat__greedy__python-mlx-lm | PASS 0.3333 | FAIL 1.0 (12/12) | DIVERGED | DRIFT_BATTERY_DIGEST_bf16__chat__greedy__python-mlx-lm |
| 4bit-requant__chat__greedy__python-mlx-lm | PASS 0.3333 | FAIL 1.0 (12/12) | DIVERGED | DRIFT_BATTERY_DIGEST_4bit-requant__chat__greedy__python-mlx-lm |
| bf16__chat__t=0.6__python-mlx-lm | PASS 0.3333 | FAIL 1.0 (12/12) | DIVERGED | DRIFT_BATTERY_DIGEST_bf16__chat__t=0.6__python-mlx-lm |

FINDING: on the raw surface EVERY G2 prompt of the removal mirror hits the 256
cap (score 1.0 >= LOOP_RATE_M 0.6667 => verdict FAIL, flipped from PASS). The
A3-certified loop-rate-down behavior does NOT transfer across the
template/battery key change — it inverts. Direction was not predicted pre-run
("cap-hit behavior may move in either direction; DRIFT_BATTERY_DIGEST (axis
TEMPLATE) plausible, confidence low-medium"). Per the PREREG-E kill clause this
is a FINDING, not a tool failure, and it does NOT invalidate the ledgered
bf16/chat/greedy/python certifications (they stay keyed to their receipts).

## Context cells (MULTI_CHANGE_CONTEXT_CELLS law — findings, never failures)

- Q cell3 (bf16__chat__t=0.6, off-axis in Q): PASS 0.4167 vs ref 0.3333,
  STABLE — identical to S cell3 (seed-0 subset-order reproduction).
- S cell1/cell2 (off-axis in S): PASS 0.3333 / PASS 0.25 — EXACT reproduction
  of Q cell1/cell2 (greedy determinism across invocations on digest-verified
  weights).
- T cells 2-3 (off-axis in T): also DIVERGED — the template flip spans quant
  and sampler variants uniformly (12/12 cap-hits in every T cell).
- PRESENCE_PENALTY_UNSUPPORTED recorded on every t=0.6 cell (paper protocol
  presence_penalty 1.5 has no mlx-lm make_sampler key).

## Engine axis detail (E)

- Wiring (seq-0 ENGINE_AXIS_WIRING): (a) machinery record = pre-run dry-run
  plan digest 8b6533a1 (rust_status READY via PARITY_RECEIPT_SHAPE_ADAPTER over
  the frozen qwen35 parity evidence 8a2b69a2, PARITY DONE per VERDICTS.md
  2026-11-06 rust-parity row); (b) LIVE rust generation reusing the EXISTING
  ws2_rust_generate release bin 068566a42e866386b6f6a9255c0a473bcca6461ecdcd87c0fb39e1c5948b161b
  (REUSED, not rebuilt) on the R mirror + chat battery: 22 cells GENERATE_OK,
  gens sha256 c29559671a9aebf58d1039b92fd962d253fe138790bf03a54f71cbcf213866bb,
  model sha fadd55fa..., power ac/ac; (c) frozen lib/src/cross_engine.dart
  certify via tool/runs/v6_certify_dart.dart f3b33064 (git-unmodified):
  verdict AGREE, python_mlxlm reference / rust candidate, bundle =
  loop_rate_G2 only, tolerance abs 0.084 rel 0.
- Rates: G2 py 0.3333 = rust 0.3333 (delta 0.0); G0 0.0 = 0.0 (context).
- Token identity: 12/22 pairs equal, 10 mismatches, 0 cap-hit flips — EXACTLY
  reproduces the WS-2 measured statistic for this mirror (12/22 equal, rates
  AGREE). The mismatches are the recorded cross-engine drift statistic
  (attribution: rust candidate argmax convention + 1-ulp kernel drift), context
  not gate. Certify output sha256
  b5feb7c4065923bb9b05b8cd61e11a62b5e995d1aabeb5e0d9506862c8696708.

## Predictions vs observed (pre-run, seq 0)

| axis | prediction | observed |
|---|---|---|
| reference | cell1 reproduces 0.3333 exactly => STABLE (high conf) | exact, STABLE |
| quant | <= 1 of 12 flips => STABLE (medium conf; DRIFT_QUANT live possible) | 1 cell DOWN (4->3 hits), delta 0.0833, STABLE |
| template | either direction; DRIFT plausible (low-medium conf) | DRIFT x3, score 1.0 (all 12 cap-hit), FAIL verdicts |
| sampler | possible DOWN drift > 1/12 (medium conf) | UP 1 cell (4->5 hits), delta 0.0833, STABLE |
| engine | rates AGREE within 0.084; ~10/22 id mismatches as CONTEXT (high conf) | AGREE delta 0; 10/22 mismatches exactly |

## Unified matrix verdict

**V-6 = DRIFT (template axis only)**: quant STABLE, template
DRIFT_BATTERY_DIGEST (3 cells named), sampler STABLE, engine STABLE.
Key-law reading: the A3 plant-1 removal certification TRANSFERS within
tolerance across 4bit-requant, t=0.6 sampling and the rust engine, and does NOT
transfer across the template/battery key change (raw surface inverts the
certified behavior). Kill clause honored: ledgered bf16/chat/greedy/python
certifications remain valid, keyed to their receipts.

## Run provenance (resume)

- Predecessor (seq 0-8): prereg registration, Batch A (rebuild REBUILD_VERIFIED
  21/21 + 4bit requant REQUANT_OK, battery power recorded as-is), Batch B
  (Q invocation, 3/3 STABLE, battery power discharging recorded). Stopped by
  the 2026-11-06 power emergency between B and C (VERDICTS.md ops rows;
  batch_C.log 0 bytes).
- Resume run (seq 9-27): MIRROR_VERIFIED_IN_PLACE (scratch intact; all digests
  == registration; no REPLAY_DIGEST_DRIFT); runners reused UNCHANGED
  (v6_matrix.py b8cfd08b frozen, v6_verdict_runner.py fc58c73b,
  v6_certify_dart.dart f3b33064, batch_qtsd.sh, append_row.py); Q
  invocation-summary durability row transcribed (seq 11); batches C/D/E under
  device lock v3 with sibling A2-finisher contention (all holds <= 20 min:
  C 316 s, D 310 s, E 131 s; waits: C attempt-1 DEVICE_LOCK_TIMEOUT 1190 s
  bounded, then 0 s acquisitions via gap observer); AC power at every launch
  boundary (power lines in lock rows; no POWER_BATTERY_STOP needed this run).
- NAMED incidents (both this resume run's errors, both recovered, both
  receipted): LOCK_RACE_MISRELEASE (seq 10 — rmdir'd a sibling's 56-s-old live
  hold believing it stale; A2 self-recovered in 34 s) and
  TASKSTOP_MID_HOLD_LOCK_LEAK (seq 12 — killed own batch script mid-hold,
  leaked lock ~2 min, manual-rmdir recovery per A2's documented route; no
  measurement impact, partial reports/T deleted and re-run clean).

## Non-claims

- All wall-clock numbers (batch_wall_s, wall_ms, hold_s contexts under
  contention) are NON-CLAIMS (contention + POWER.md law; sibling A2 arm shared
  the device throughout).
- V6_TASK_LEG_NOT_RUN (task-success leg not re-evaluated under key changes).
- PRESENCE_PENALTY_UNSUPPORTED (recorded on t=0.6 cells).
- n=12 G2 cells caps every rate at 1/12 granularity; no generalization claim
  beyond the frozen battery.
- RNG_CELL_ORDER_DEPENDENCE: seed 0 pins the frozen subset cell ORDER within an
  invocation, not per-cell independence.
- Scratch: mirrors + fixtures swept after the run per the probe scratch law;
  durable evidence is textual (this file + the chained rows + repo receipts).
