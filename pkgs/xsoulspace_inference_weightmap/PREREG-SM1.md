# PREREG-SM1 — sparse-mask proposer pilot (heatmap-guided vs random), FROZEN 2026-11-08

Status: FROZEN before any sample run (owner go 2026-11-07 "implement all
stages and apply recommendations"; SM-1 was documented-not-frozen in
PREREG-G §9). Answers ONE question: does heatmap-guided column selection
find loop-reducing edits FASTER than random selection at matched budget?
(Passive localization failed three ways in this program — P-3 ×2, WS-3 —
so the index question is asked as an INTERVENTION-BASED proposer test.)
Descriptive pilot: NO certification; any improving sample is a CANDIDATE
repair feeding a future stage via NEW prereg only.

Cast/key: Qwen3.5-0.8B BASE, PREREG-G §5 key (base digest, tokenizer, engine
= this runner @sha256, greedy sampler, caps). Edit surface:
`model.language_model.layers.{15,19}.mlp.down_proj.weight` (A1-confirmed
tensors, [1024, 3584]).

## 1. Heatmap (frozen construction)

- Banks: LOOP = the 12 G2 cells of cells_frozen_A3.json @cap 256 (stage-1
  fact: base cap-hits 12/12); NEUTRAL = first 8 G1 perm cells @cap 64.
- Captures via FROZEN tool/eval/capture_activations.py on the BASE at
  layers 15,19 (device step, AC-gated, lock-batched).
- Per-layer direction via FROZEN tool/runs/a3_propose.py (diff-of-means,
  unit) — never reimplemented.
- Column scores: `score(c) = |Σ_r W_down[r,c] · dir[r]|` over the 3584
  intermediate columns — the per-column contribution of the recovered
  direction through the down_proj weights (static, capture-derived; NAMED
  G3_SM1_HEATMAP_COLUMN_PROJECTION). Computed CPU-side from the direction +
  base safetensors; digest-recorded before any sampling.

## 2. Sample space (frozen; fitness-blind pre-draw)

Candidate edit (per sample): per-layer sidecar delta on k=8 columns —
direction = the layer's unit heatmap direction (all 1024 rows), columns =
the sample's draw, sign = removal (−), scale = 4.8 single (A3 primary scale;
NAMED CROSS_CAST_TRANSFER_ASSUMPTION_S4.8 carried from P-2; never
select-best).

Arms (samples pre-drawn AFTER the heatmap exists and BEFORE any fitness
measurement — sampling is fitness-blind; all draws digest-recorded in
`sm1_samples.json` before the first mirror):
- GUIDED: 12 samples, columns sampled without replacement ∝ score over all
  3584 (seed = 20261108·1000 + i).
- RANDOM: 12 samples, 8 columns uniform over 3584 (seed offset +1000000).
- SHUFFLED-HEATMAP control: 6 samples, guided procedure with the
  column→score pairing permuted by a fixed seeded permutation (breaks the
  score↔column association while preserving the score distribution) — the
  chance control, WS-3 k=3 precedent shape.

## 3. Fitness (frozen)

- Primary: cap-hit count over the FIRST 6 G2 cells @cap 256 (base R0 = 6/6
  by stage-1 receipt). Sample fitness = 6 − cap-hits (cells improved).
- Guard: first 4 G1 cells @cap 64, base pass probed ONCE before samples and
  recorded; if base pass < 3/4 → named GUARD_FLOOR_LIMITED, proceed
  fitness-only (the stage-1 lesson applied prospectively).
- Per-sample device flow: apply_delta (FROZEN tool) → make_mirror (FROZEN
  tool, $TMPDIR mirror root) → greedy gens via FROZEN
  wm_qwen35_generate.py → per-cell rows. Every sample journaled
  (sample manifest jsonl: arm, seed, columns, mirror path, per-cell
  cap_hit/pass, wall_ms_claim:false, power facts per batch).

## 4. Verdict classes (frozen, descriptive)

- GUIDED_BEATS_RANDOM: best GUIDED fitness > best RANDOM fitness by ≥1 cell
  AND mean GUIDED > mean RANDOM. 
- CHANCE_CONTROL_OK / CHANCE_CONTROL_LEAK: shuffled-arm best/mean vs guided
  (a shuffled sample matching guided best = the heatmap carries no
  column-specific signal).
- NO_SAMPLE_IMPROVES: every sample ≤ base on the primary.
- DETERMINISM_DRIFT: re-measure of the best GUIDED sample (mirror rebuilt,
  regen) not exactly reproducing.
- PARTIAL-with-denominator allowed (budget stops between samples;
  resume-safe). Full denominator journaled regardless.

## 5. Implementation + laws

`tool/runs/sm1_run.py`: subcommands `probe` (device: captures + propose +
column scores + fitness-cell base probe + sample pre-draw →
`sm1_state.json` digest-recorded), `run` (device: consume frozen samples,
per-sample subprocess under per-sample lock batch v3, manifest resume,
POWER gate AC-only with 300s×12 polling then
POWER_GATE_BATTERY_WAIT_EXHAUSTED), `verdict` (CPU pure from the manifest).
CPU-only unit tests pin the pure parts (score-proportional sampling, shuffle
permutation, fitness tally, verdict classes, chain writer). Frozen tools
reused via subprocess, never edited; PYTHONDONTWRITEBYTECODE=1; scratch
$TMPDIR; named exits; no commit by the runner.
