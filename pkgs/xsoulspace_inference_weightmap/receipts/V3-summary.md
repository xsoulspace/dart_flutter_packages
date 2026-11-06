# V-3 summary — PREREG-D cross-cast replication LIVE (second cast, K=4+4)

Date: 2026-11-06 (UTC). Actor: zcode V-3 (session seat, branch ag-c, no
commits). Pre-registration: `PREREG-D.md` V-3 + **Addendum 2026-11-06b**
(numeric pins FROZEN pre-run) + this run's plan row `receipts/V3-run.jsonl`
seq 0 (digest `caa087c6f6cba0a0dca1181780a6bd68476af78605819638b6d2c864ff42383f`),
written BEFORE any measurement. Frozen criterion for the arm stage: >= 3/4
plants certified (loop-rate down AND task-success not down on this cast's own
frozen cells) AND 4/4 nulls NOT certified => REPLICATION PASS on second cast.

## HEADLINE

**V-3 on the local candidate casts ends at the pilot gate:
`SCALE_UNCALIBRATABLE` on qwen3-1.7b-4bit (a verdict, not a defect; run stops
with rows per the frozen rule). Candidate 1 (lfm25-1.2b) was excluded earlier
as `ARCH_UNSUPPORTED`. No arms ran on any second cast (denominator 0/8), the
blinding key was never cut, and NO replication PASS/FAIL verdict exists for a
second cast.** The A3 primary-cast PASS (6/8 + 8/8) is untouched; the
cross-cast replication criterion (>= 2 casts) is NOT met this arc.

## Candidate pre-check table (candidates in frozen order)

| # | candidate | hub snapshot | arch facts | pre-check outcome | named verdict |
|---|---|---|---|---|---|
| 1 | lfm25-1.2b | models--LiquidAI--LFM2.5-1.2B-Instruct-MLX-4bit @ 7ccafdb0 | Lfm2ForCausalLM, 16 layers, hidden 2048, inter 12288, 4bit; MLP = `feed_forward.w1/w2/w3`, NO `.mlp`, 0 `mlp.down_proj` tensors (48 packed `feed_forward.w2.*`) | mlx-lm 0.32.2 loads + generates at runtime (ok); FROZEN capture_activations.py exits 1 `ARCH_SHAPE_UNEXPECTED: layer 10 has no .mlp`; frozen oracles read-only => unhostable | **ARCH_UNSUPPORTED** (loop-rate not measured — moot after arch exclusion) |
| 2 | qwen3-1.7b-4bit | models--mlx-community--Qwen3-1.7B-4bit @ 3b1b1768 | Qwen3ForCausalLM, 28 layers, hidden 2048, inter 6144, 4bit packed | DEQUANT_BASE adaptation (below); G2 loop-rate: hub-4bit original **4/12 = 0.3333** (reference), dequant pipeline base **5/12 = 0.4167 >= 0.25** | **PRE-CHECK PASS** — selected as second cast; then pilot ladder **SCALE_UNCALIBRATABLE** |

Layer mapping rule (recorded PRE-RUN, seq 0): `layer = round(f × L_total)`,
f ∈ {15/24, 19/24} → qwen3-1.7b (28): **18, 22** (round(17.5)=18 half-up,
Python-round identical; round(22.167)=22). lfm25 (16) would have been {10,13}
(recorded, moot).

## NAMED adaptations / issues (all pre-run-recorded in seq 0 unless noted)

- **DEQUANT_BASE**: the 4bit packed store is refused by the frozen builders
  (apply_delta header law: columns 0..6143 out of range for packed
  [2048,768]; make_mirror/repair merge law casts to the stored dtype).
  Adaptation = `mlx_lm.utils.dequantize_model` (standard deterministic
  lossless route) → bf16 single-shard base (3.2 GB) in `$TMPDIR/wm-v3`
  (probe scratch law); hub store read-only; digest
  `6a6894aab26ea953d0f3f404578327c18874d8dd68456aceadf932035c8afcc3`.
  All measurements ran on this base; swept after the verdict (rebuildable).
- **CAST_DTYPE correction (honest)**: seq 0 pre-recorded fp16 as the expected
  dequant dtype; observed store dtype is **bfloat16** (hub scales are bf16) —
  same dtype class as the A3 cast; correction row seq 2, no rule changed.
- **CONFIG_QUANTIZATION_RESIDUE** (seq 3): first base-stage attempt failed
  FAST at model load — hub config carries BOTH `quantization` and legacy
  `quantization_config` (no `quant_method`); v3_dequant popped only the
  former. Fixed (config minus both keys; new sha `1ddb5b89…`); weights
  untouched; zero measurements affected.
- **ATTEMPT1_UNRECEIPTED** (seq 5): the first base-stage launch sat ~46 min
  in the 10 s acquisition loop under continuous external batch chaining and
  was killed before its 1 h cap to relaunch under the receipted lock-timeout
  path (v3_base.py/v3_pilot.py amended; digests a29c4920…/e390cb4b…). That
  first wait left no receipt file — recorded honestly here and in seq 5.
- **DIGEST_LINEAGE_NOTE / BUILDER_DIGEST_NOTE**: recorded in seq 0
  (a3_battery.py current == git HEAD `7c444278…` vs V12-recorded `ee409d76…`;
  make_mirror.py `271c1f04…` = the instrument-fixed builder of all A3 arm
  mirrors + WS-1 replay).

## Base stage (dequant pipeline base)

Captures (frozen, layers 18/22, 128+128 bank prompts, MLP-input means;
tokens 2088/1400), frozen proposer diff-of-means directions: L18
diff-norm 16.366209 (sha `af3236ef…`), L22 22.969910 (sha `b5844501…`).
Full frozen battery G0,G1,G2,pilot: **G2 base loop 5/12 = 0.4167**
(pre-check of record), pilot base 4/16 = 0.25, lock wait 270 s receipted,
device ~5.7 min (< 20 min law).

## Pilot ladder (frozen rule: FIRST scale with lift >= +20pp wins; ALL rows recorded)

Base pilot loop-rate 4/16 = 0.25; columns `pair_columns_v3(1)` (seed-20261105
procedure, range 6144; sha `23bfc08a…`); direction = base diff-of-means
L18/L22; mirrors verified per step (MIRROR_OK; 308/310 unedited identical;
edits confined to the 64 columns; bf16 absorption ~0.3–0.4% — the edit
landed at full strength).

| scale | loop (hits/16) | lift | verdict |
|---|---|---|---|
| 0.05 | 0.25 (4/16) | +0.0pp | row |
| 0.1 | 0.25 (4/16) | +0.0pp | row |
| 0.2 | 0.25 (4/16) | +0.0pp | row |
| 0.4 | 0.25 (4/16) | +0.0pp | row |
| 0.8 | 0.25 (4/16) | +0.0pp | row |
| 1.6 | 0.3125 (5/16) | +6.25pp | row |
| 2.0 | 0.3125 (5/16) | +6.25pp | row |
| 3.2 | 0.25 (4/16) | +0.0pp | row |
| 4.8 | 0.3125 (5/16) | +6.25pp | row — ladder exhausted |

**Verdict: SCALE_UNCALIBRATABLE** (max lift +6.25pp = a single cell flip;
weak, non-monotone dose-response). Contrast: the same frozen pipeline on the
A3 primary cast (qwen3-0.6b-bf16) reached +50pp (11/16) at s=4.8 — the 1.7B
cast behaviorally resists the loop phenotype at every frozen ladder scale.
Extending the ladder (A3 needed a pre-registered v2 amendment up to 12.8)
would require a NEW prereg row — owner decision, not exercised here; the
frozen-rule outcome stands as the verdict.

## Not run (pilot gate halt; denominator honest)

Truth/blind build (seed 20261106-V3 recorded pre-run, key NEVER cut), 4+4
arms, random-proposer controls (CONTROL_LEAK check), WS-3 prior on a plant
mirror (retired-backbone), verdict freeze/unblind/join, concordance
criterion — **0/8 arms; criterion NOT evaluable**. The K=4+4 design (incl.
null-3-style contrast-null exclusion per the V-1 NULL_LEAK row) stays
pre-registered in seq 0 for any future re-preregistered run.

## Device / lock accounting (protocol v3; waits receipted, non-claims)

Serial -j1 throughout; `mkdir ${TMPDIR}/wm-device.lock` per batch; 10 s
acquisition-only retries (v3-authorized); rmdir + 3 s courtesy. Waits:
arch probe 2410 s; dequant 0 s; 4bit-ref 0 s; base attempt-1 ~46 min
UNRECEIPTED (killed pre-cap, named); base attempt-2 270 s; pilot step 1
1000 s, steps 2–9 0 s. Heavy external contention (WS-4 actor chaining
~15–20 min batches) throughout. Power: AC 95% charging at every tag.
All wall_ms rows tagged wall_ms_claim=false.

## Evidence

- Ledger: `receipts/V3-run.jsonl` (hash-chained, 8 rows: run-plan, 4
  pre-check rows, pilot, final; CHAIN_INTACT verified at every append).
- Artifacts: `receipts/V3/` (arch probe, dequant + config-fix receipts,
  4bit-ref battery, base stage receipt + directions + battery, pilot receipt
  + 9 mirror receipts + 9 pilot batteries, tmpdir manifest).
- VERDICTS.md: V-3 section (2 pre-check rows + 1 final row).
- Frozen tools ran UNMODIFIED (digests pinned in seq 0): capture_activations,
  apply_delta, a3_propose, a3_battery, make_mirror, a3_score-family not
  reached, ws3 not reached; new V3 wrappers (`tool/runs/v3_*`) only wrap.
