# PREREG-G — G-3 revision-dynamics ladder (sampler-side loop interventions)

Status: FROZEN 2026-11-07 (owner work order: "document it as separate experiment
and implement it"). Stage: PILOT frozen; pathology stage conditional (§7).
Live-run gate: AC power only (POWER rule; fleet law 2026-11-06). Nothing in
this document authorizes resuming the owner-paused arms (V-1v2, A2, P-2, V-6
task leg) — those keep their own resume pointers.

Cast: Qwen3.5-0.8B BASE (unedited). Engine: Python-boundary custom step loop
(`tool/runs/g3_revision.py`, mlx-lm 0.32.2) — python-first house law; a Rust
separate-file port with parity digests is POST-VERDICT work, named non-goal of
this stage. Frozen oracles: `cells_frozen_A3.json` (never edited; a change =
new prereg row).

## 0. Hypothesis (pre-run)

H-G3: on the qwen3.5-0.8b base, sampler-side revision dynamics (soft-mixture
decode; detect-and-resample rewind) measurably MOVE the loop phenotype
relative to greedy, on cells where greedy loops. Mechanism prediction, written
before any run: any movement is ATTRACTOR SMOOTHING (dynamics-level), not
added capability — the obstacle law is decoder-invariant, and the
single-threaded-reasoners probing result (arXiv 2025-08-05) says mixture
decode tracks the greedy path. The pilot therefore validates the INSTRUMENT
and measures movement; it certifies nothing (§6).

Literature anchors (fetched 2026-11-07): soft thinking (training-free,
2025-05-21, +2.48pp pass@1 ≥7B casts); stochastic soft thinking
(Gumbel-Softmax, "Greedy Pitfall"); Coconut [2412.06769] and recurrent-depth
[2502.05171] = TRAINED latent loops (context for why this ladder stays
sampler-side and training-free); no training-free revision-dynamics arm for AR
text found in the fetched set — this ladder is the open-slot contribution.

## 1. Arms (frozen; no arm added/removed/retuned within the stage)

| Arm | Rule (frozen constants) |
|---|---|
| R0 | greedy: f32 log-softmax (`logits − logsumexp`, cast f32 — G3_ARGMAX_F32) → argmax. Baseline + instrument continuity. |
| R1 | repetition penalty 1.2 over the last 64 sequence tokens (prompt+generated, mlx convention: `l>0 → l/1.2`, else `l*1.2`), then greedy. THE BORING CONTROL. |
| R2 | soft mixture: top-k=32 softmax probs renormalized; next input = Σ p̂ᵢ·E[tokᵢ] via `input_embeddings` (f32 accumulate, cast to weight dtype — G3_MIXTURE_F32_ACCUM); recorded token = hard readout (same argmax rule as R0) — G3_SOFT_MIXTURE_TOPK32_HARD_READOUT. |
| R3 | detect-and-resample: greedy until detector fires (§3); rewind-to = first-occurrence-end of the trigger 4-gram in the generated span (rewind_to = p0+4); RECOMPUTE_REWIND (fresh caches, full re-prefill of prompt+kept tokens — correct for GDN recurrent state by construction; cost receipted); then resample window W=16 tokens at temp 0.9 (`mx.random.categorical` on f32 log-softmax/temp, per-intervention seed = 20261107·1000003 + cell_idx·1009 + intervention_idx — RNG_ENGINE_MX_RANDOM, engine-version-dependent, receipted); after the window, greedy resumes. Max interventions I=3 per cell; detector firing after I → run to cap, recorded. |
| NULL-A | random-rewind control: intervenes when generated length first exceeds {48, 96, 144} (same budget I=3, decoupled from the detector); rewind_to = uniform in [max(0, L−32), L−8] via `random.Random(20261107·1000 + cell_idx·7 + int_idx)` (python RNG, seeds recorded); same W=16/temp-0.9 window as R3. Tests whether REWIND-PLACEMENT intelligence matters or any stochastic interruption suffices. |

EOS: stop on any id in the mlx-lm tokenizer wrapper's reported eos set
(expected {248046 `<|im_end|>`}; actual set recorded in the arm receipt as a
NAMED FACT, not a tunable). Surface: frozen A3 render —
`apply_chat_template([{role:user, content:prompt+' /no_think'}],
add_generation_prompt=True, tokenize=False)` with the qwen3.5-0.8b tokenizer
(G3_SURFACE_PORT_FROM_A3: cells were designed on qwen3-0.6b-bf16; R0 measures
whether they still induce loops on this cast — headroom precondition §6).
Rendered cell-0 prefix sha256 recorded per arm receipt.

## 2. Cells and caps (frozen source, digest-verified at every launch)

Source: `tool/runs/cells_frozen_A3.json`
sha256 `8406130623b6e85922eac6cbd92b73dd2282e6fc19538bb3c199f647f518d760`.
Digest mismatch at launch = named refusal CELLS_DIGEST_DRIFT (frozen-oracle
law), never a silent continue.

- Primary (loop-propensity class): all 12 G2 cells, cap 256 (cell-file caps).
- Task guard: first 8 G0 cells in frozen file order, cap 64. Guard question:
  does the revision sampler break ordinary task behavior?
- Pilot denominators: 5 arms × (12 + 8) = 100 cell-runs. Every row journaled
  (manifest + ledger); no post-hoc exclusions.

These are SOLICITED-loop cells ("repeat forever") — movement on them is
mechanism evidence, NOT pathology repair. The pathology class (UNSOLICITED
loops: MATH cells, base cap-hits 91.7% @4096 measured in A2; 80/88 @1024 in
P-2) is stage 2, conditional (§7). This distinction is frozen: a pilot win is
never reported as "fixed looping".

## 3. Loop-signature detector (frozen spec; dual implementation)

Over GENERATED token ids only (prompt excluded): n-gram n=4; window = last 64
generated ids; fires at position t when the just-completed 4-gram
`ids[t−3..t]` has ≥3 distinct occurrences starting within the window.
Runtime use: R3 intervention trigger (incremental = same function on the
prefix). Offline use: scorer runs the identical spec over recorded ids for
EVERY arm (uniform measurement, arms do not self-report). Both
implementations (python in the runner, Dart in the scorer) are pinned by
shared golden vectors `tool/runs/g3_detector_golden.json` in both test
suites; a golden mismatch = named refusal, never a fix-in-place.
Parameters are frozen here; a retune = addendum + new denominator.

## 4. Metrics (frozen)

- cap_hit_rate per arm×group = `tokenLimitRate` over per-cell generated-token
  counts (FROZEN `lib/src/scorers.dart`, run never edited) — primary.
- loop_signature_rate per arm = fraction of cells with ≥1 offline trigger;
  first_trigger_position recorded per cell.
- median generated tokens per arm×group.
- G0 guard success per arm = A3-frozen cell scorers (label/string first line,
  numeric_final via frozen mathScore; think_prefix_strip convention copied
  verbatim from `a3_score.dart`).
- interventions_total per arm (R3/NULL-A), recompute cost rows.
- Determinism cross-check: R0 re-run on the first 4 G2 cells must reproduce
  cap-hit and generated-token counts exactly (A2 determinism precedent);
  mismatch = named DETERMINISM_DRIFT row, stage verdict capped at
  INSTRUMENT_UNVALIDATED.

## 5. Certification key (per row; V-6 key law)

{base: Qwen3.5-0.8B hub snapshot `main`, FETCH-RECEIPT.sha256 file sha256
`17f7fd5d45b7b8707606e3488cff31ba282abceb55541458315936fbd7915834` (runner
re-verifies at launch), tokenizer: mlx-lm wrapper over snapshot, quant: none
(bf16 store), surface: chat+/no_think render (cell-0 prefix digest recorded),
engine: python g3_revision.py@sha256 (recorded per arm), sampler: per-arm spec
above, caps: 256/64}. Outside this key = a new claim; no transfer to the Rust
engine, other surfaces, or other casts without re-certification (V-6
DRIFT-template-only is the standing evidence that surfaces matter).

## 6. Preconditions, floors, kill rules (frozen pre-run)

1. HEADROOM PRECONDITION (saturation lesson applied PROSPECTIVELY, V-1v2
   plant-3 precedent): R0 cap-hit on G2 must be ≥9/12. Below → cell class
   HEADROOM_REJECTED on this cast; pilot verdict = INSTRUMENT_ONLY and stage 2
   (pathology cells) becomes the primary measurement. Recorded either way.
2. MOVEMENT criterion (per arm vs R0, primary contrast): |Δ cap-hit cells| ≥4
   of 12 AND offline loop-signature rate moves in the same direction by ≥25%
   relative. Both clauses required; near-misses are data, not movement.
3. GUARD KILL (arm-level, not program-level): any arm with G0 success < R0
   G0 success − 1 cell → GUARDRAIL_FAIL for that arm (recorded; the arm's
   movement row rides with the failure).
4. KILL RULE (the cheap honest verdict): if R1 satisfies MOVEMENT and both
   R2 and R3 cap-hit rates are within 1 cell of R1's → stage verdict
   SAMPLER_GENERIC: "attractor smoothing is sampler-generic; mixture/rewind
   machinery adds nothing beyond repetition penalty". This is a SUCCESSFUL
   verdict of the design, not a program failure.
5. R2 capability gate: `input_embeddings` path source-verified pre-freeze
   (qwen3_5.py L272-273, TextModel passthrough L334, Model L415-422); a
   runtime failure = EMBEDS_RUNTIME_FAIL → arm BLOCKED row, other arms
   proceed (errors NAMED, never silent).
6. NO CERTIFICATION FROM THE PILOT: certification shape (loop-down ∧
   task-not-down on frozen cells with saturation headroom and disjoint probe
   sets) belongs to stage 2. The pilot's possible verdicts:
   INSTRUMENT_VALIDATED + per-arm movement facts; SAMPLER_GENERIC;
   HEADROOM_REJECTED; INSTRUMENT_UNVALIDATED (determinism drift);
   BLOCKED-partial with denominator.

## 7. Staging and resume

- Stage 1 PILOT (frozen here): 5 arms × 20 cells, cap 256/64, est. device
  wall ~20–35 min incl. rewinds (absolute ms = non-claims per POWER.md).
  Per-arm lock batches (protocol v3: acquisition-only 10s retries, rmdir+3s
  courtesy, LOAD-AFTER-LOCK — model loaded inside the acquired section, one
  subprocess per arm, orchestrator holds no mlx import). Manifest resume:
  completed (arm, cell) rows never re-run; completed arms never re-launched.
- Stage 2 PATHOLOGY (conditional on stage-1 instrument validation; requires
  its own addendum row freezing the cell source): unsolicited-loop MATH cells
  (A2 capcurve prompts re-frozen into the repo, or the paper exp8 pool
  re-fetched and frozen as `cells_frozen_G3_pathology.json` with digest before
  any run) @ cap 1024; verdict shape = cap-hit reduction ∧ MATH-score
  not-down (frozen scorers), disjoint localization/certification/
  generalization split per probe law.
- Stage 3 (documented only): R4 masked-parallel two-pass; Rust separate-file
  port with bitwise/distributional parity digests.

POWER GATE (frozen): live launch only on AC power (`pmset -g ps` = AC,
recorded in the receipt); battery launch = named refusal POWER_GATE_BATTERY.
Staged launch command (single line, resume-safe):

```
cd pkgs/xsoulspace_inference_weightmap && PYTHONDONTWRITEBYTECODE=1 \
  nohup ~/.local/share/wm-mlx/bin/python -I tool/runs/g3_revision.py \
  --model ~/.cache/huggingface/hub/models--Qwen--Qwen3.5-0.8B/snapshots/main \
  --stage pilot --out "$TMPDIR/g3-artifacts/run" > "$TMPDIR/g3-pilot.log" 2>&1 &
```

Scoring (CPU-only, after the pilot):

```
dart run tool/runs/g3_score.dart --state "$TMPDIR/g3-artifacts/run" \
  --cells tool/runs/cells_frozen_A3.json --out receipts/G3-run.jsonl \
  --summary receipts/G3-summary.md
```

Addendum 2026-11-07b (post-freeze, SURFACE-ONLY): the scoring CLI shipped as
`--state <run-dir>` (the parent of `gens/` + `manifest.jsonl`; the scorer
needs the manifest for blocked/failed arm rows), not `--gens <dir>` as
originally sketched above; §7 command corrected in place. No arm, cell,
constant, floor, precondition, or kill rule changed — this addendum touches
the invocation surface only, recorded per frozen-oracle law rather than
edited silently.

## 8. Statistical governance

Denominator journal: every cell-row in the manifest, every verdict in
`receipts/G3-run.jsonl` (hash-chained via frozen `lib/src/ledger.dart`),
stage rows in VERDICTS.md. Multiplicity: primary contrasts = 4 (R1, R2, R3,
NULL-A vs R0) on cap-hit; pilot is descriptive (movement criterion); Holm
applies at stage 2. Blinding: not applicable (mechanical arms, no proposer
narratives); scoring reads only recorded ids/text — arms cannot self-report.
Probe-scratch law: gens/receipts scratch under `$TMPDIR/g3-artifacts`;
durable evidence textual in `receipts/`.

## 9. Documented-not-frozen (own prereg row required before any run)

- **S-1 activation-steering overlay**: runtime additive steering vectors
  (CAA/RepE shape) supplied as DATA (vector+scale+layer) from Dart; engine
  addition only — kill-clause clean ("MLX adds speed, never meaning"). L2
  rung; hooks exist (`capture_activations.py`), injection hook = small
  additive engine feature.
- **G-4 ReLIT-shape recursion overlay**: frozen qwen3.5-0.8b backbone + small
  TRAINED recursive block (arXiv 2608.08113 shape); acceleration-lane LoRA
  bet on planning-shaped cells; arithmetic cells = declared non-claims.
- **SM-1 sparse-mask proposer** (owner idea 2026-11-07, "heatmap-guided
  picking and multiplying of weights"): black-box search over sparse
  multiplicative weight masks, sampled random vs heatmap-biased (diff-of-means
  column scores from the frozen capture instrument = the heatmap), fitness =
  frozen loop cells, denominator-journaled per sample. Design sketch: paired
  guided-vs-random at matched sample budget, chance-controlled (WS-3 k=3
  precedent), norm-matched nulls, saturation precondition, disjoint cert
  cells. Family anchors: MeZO/SPSA zeroth-order finetuning; SNIP/RigL
  saliency-masked sparse training; MC-dropout (inference-time random weight
  masking on non-dropout-trained models = OOD degradation, predicted monotone
  — its own cheap falsifiable arm if ever run); weight-space diffusion
  [2507.10623] = trained generator over weights, named non-goal at fleet
  scale. Critical read lives in the session record; a run needs this section
  promoted to a frozen arm spec first.
- **Folding/overlay op-family note** (owner question 2026-11-07): additive
  overlay (task arithmetic) and interpolation/folding (SLERP/TIES-shape) are
  already inside the frozen patch algebra's op vocabulary (additive deltas
  proven end-to-end in A3/WS-1; multiplicative scale sweeps proven in the
  sensitivity triple); the binding constraint is the oracle + obstacle law,
  not the op type. A folding arm on sibling checkpoints = G-1 territory.

## 10. Non-claims (written before any result)

No capability-addition claim from any arm. No "fixed looping" claim from
solicited-loop cells. No transfer across engines/surfaces/casts (key law).
No parity-with-literature pass bar (soft-thinking papers ran ≥7B
thinking-trained casts; a null at 0.8B is an expected-shape result, not a
refutation of the literature). Absolute wall-ms = non-claims. A
SAMPLER_GENERIC or HEADROOM_REJECTED verdict is a successful cheap outcome
of the design.

## Addendum 2026-11-08b (owner override; surface-only)
Owner authorized battery device runs 2026-11-08: `--allow-battery` additive flag on the orchestrator (default UNCHANGED = AC-only gate stands); 20% battery floor enforced at the chain level. Rules unchanged.
