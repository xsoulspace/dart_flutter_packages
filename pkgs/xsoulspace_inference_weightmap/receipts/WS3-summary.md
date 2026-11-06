# WS-3 LIVE summary — masked-attribution prior on plant-1 (2026-11-06)

**PROPOSE-ONLY LAW: the prior NEVER certifies; it only ranks candidate layers.**

Question: does the WS-3 masked-attribution prior localize the A3 plant-1 planted
layers {15, 19} in `model.layers.{15,19}.mlp.down_proj` (scale 4.8, 64 columns)?

Pass criterion (FROZEN, PREREG-D WS-3 + addendum 2026-11-06): >=1 planted layer
in the prior's top-3 on the plant mirror; k=3; chance 3/24 per mirror; base
(unplanted) bf16 mirror = control, top-3 recorded but NOT scored; family-wise
binomial across mirrors actually run (live scope this arc: plant-1 + base only).

## VERDICT: FAIL(chance)

## Mirror replay (digest gate)

- Rebuilt from the ORIGINAL A3 arm-002 sidecars (`$TMPDIR/wm-a3/blind/arm-002/sidecars/{L15,L19}`,
  direction shas `626d6f0c…`/`6aacf1ac…` verified pre-build) with the unchanged
  A3 builder `tool/runs/make_mirror.py`.
- Rebuilt `mirror_shard_sha256` = `22e52d07164ca45f379ccb7ddc42e52a39ec719f73e3d043a3551baa931f02e7`
  = arm-002 recorded digest (mirror_receipt sha `a93303a8…`, join-table + A3 ledger seq 5).
  **MATCH — no REPLAY_DIGEST_DRIFT.** V1–V4 green: base unchanged
  (`bfe05e58…` before/after), 308/308 unedited tensors identical, edited rows
  reproduce exactly (65247/289 and 65353/183 differing/absorbed elements).
- Base control = HF snapshot `models--mlx-community--Qwen3-0.6B-bf16` (read-only;
  digest verified unchanged after its run).

## Subset rule (pre-registered BEFORE any run; no results inspected)

First 24 lines (file order) of `prompts_localization_neutral_A3.txt`
(`a92c0f65…`) + first 12 lines of `prompts_localization_loop_A3.txt`
(`a827b253…`); subset digests `acdd689e…` / `3e6e808e…`; recorded in
`WS3-live.jsonl` seq 1 and `$TMPDIR/wm-ws3/PRERUN-subset-rule.json` before the
rebuild. Machinery frozen: `ws3_masked_attribution.py` sha `639607e8…` = frozen
digest; ridge lambda 1e-3; (24+1)x36 = 900 prefills per mirror; hooks VERIFIED
at runtime (`model` -> `Qwen3Model`, `.layers[i].mlp` shims, `.norm` recorder) —
no HOOK_POINT_MISSING.

## Results (24-layer frozen window; scores = mean MSE(loop) − MSE(neutral))

| mirror | top-3 (layer, score) | planted L15 | planted L19 | margin |
|---|---|---|---|---|
| plant-1 (scored) | L2 217.93, L0 71.13, L1 21.57 | rank 9 (18.72) | rank 20 (16.46) | −2.85 vs top-3 cutoff |
| base bf16 (control, unscored) | L2 263.69, L0 73.42, L17 26.56 | rank 17 (23.03) | rank 22 (22.33) | n/a |

Binomial (recorded per addendum): n=1 scored mirror, 0 successes;
P(>=1 hit | frozen chance 3/24) = 0.125 (exact hypergeometric null for >=1 of
2 planted layers: 0.239). With one mirror the family-wise binomial cannot reach
p<0.05 either way; extension to more mirrors requires a new pre-registered row.

## NAMED issues

1. **PREREG_WINDOW_NOTE** — PREREG-D froze "24 text-tower layers" + chance 3/24;
   the actual cast qwen3-0.6b-bf16 tower has 28 layers (A3 run-plan
   `layers_total=28`). Ran the literal frozen window `--layers 24` (masks layers
   0..23; both planted layers inside; preserves the frozen chance line and the
   ~900-prefill plan). Layers 24..27 are outside the pre-registered window; a
   28-layer variant needs a new row.
2. **BUILDER_DIGEST_NOTE** — current `make_mirror.py` sha `271c1f04…` differs
   from the seq-0-recorded `1f71892e…`; the delta is the pre-measurement
   instrument fix recorded in the A3 pilot-v1 ledger row (0444 chmod;
   array_equal + f32-cast digests), i.e. the builder actually used for all A3
   arm mirrors. The replay gate is the mirror shard digest: MATCH.
3. **LOCK_INTERVAL_SWITCH** — rebuild acquisition began at 60s backoff per task
   text (780s, 13 attempts); observed A2 inter-chunk release/re-acquire cycling
   with sub-60s gaps = the starvation pattern protocol v3 was issued for;
   switched to the v3-authorized acquisition-only 10s retry (then: rebuild
   320s/33 attempts; plant run 80s/9 attempts; base run 470s/48 attempts).
   All waits + `retry_interval_used` recorded; rmdir release + 90s courtesy
   after every batch; serial −j 1.
4. **OBSERVATION_EARLY_LAYER_DOMINANCE** — both mirrors' priors are dominated
   by the same early layers (plant top-3 = 2,0,1; base = 2,0,17; L2 score
   ~5–10x the cutoff). The loop-vs-neutral prediction-error delta tracks
   generic representational-disruption magnitude (masking early MLPs destroys
   the final representation most), not the planted/loop-specific circuitry: the
   plant moved L15 only from rank 17 (base) to rank 9 (plant). Observation
   about the prior's backbone, not a criterion change; FAIL(chance) stands as
   pre-registered. This does NOT touch the A3 diff-of-means proposer (PASS) —
   propose-only law: no certification was at stake.

## Environment

venv `~/.local/share/wm-mlx/bin/python` (python 3.12, mlx 0.32.4, mlx_lm 0.32.2,
numpy 2.5.4); power AC 95% charging before/after each run; load ~3–4; wall
times: plant 54s, base 50s (wall_ms non-claims under load). Artifacts:
`receipts/WS3-live.jsonl` (seq 0 banner, 1 pre-run subset rule, 2 mirror
replay, 3–4 run rows, 5–52 per-layer rows both mirrors, 53 summary); scratch
`$TMPDIR/wm-ws3/` (mirror, machinery outputs, drivers, PRERUN receipt).
