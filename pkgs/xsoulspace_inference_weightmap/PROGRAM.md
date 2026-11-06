# Weightmap Validation Program

Status: Phase A COMPLETE (A1 verdict ledgered; A3 PASS 6/8 sensitivity, 8/8
specificity at full denominator; A4 frozen; A2-local in flight), Phase B/C live
runs in flight, Rust qwen3_5 parity DONE bitwise. Owner: Antonio. Package:
`pkgs/xsoulspace_inference_weightmap` (isolated, removable).

## 0. Thesis and the unit of validation

Weight-space concept editing (per the MIT weight-space-programming paper,
2026-11-02) is real at LLM scale ONLY as obstacle removal via structured
low-rank direction operations, verified against frozen behavioral oracles.
The paper validated single edits against its own benchmarks with no ground
truth, no controls, no replication (n=1 frontier model). This program validates
the **pipeline that produces edits**, against ground truth we manufacture
(planted obstacles) and ground truth the paper published (released logs and
checkpoints). A single edit verdict is an anecdote; the program's claim is a
measured error rate.

Three laws inherited, never re-litigated here:
- **Obstacle law** (paper's own Gemma control): editing removes obstacles that
  hid abilities; it cannot add abilities. Product scope = repair, suppression,
  steering, graft.
- **Oracle law**: no edit claim without a frozen behavioral oracle. Nobody
  edits their own checker.
- **Propose-only law** (pattern exp 0007 / ADR 0018): predictors and screeners
  change cost, never verdicts. Floats and embeddings may change speed, never
  results.

## 1. Layers

| Layer | Content | Status |
|---|---|---|
| WS (vertical slice) | WS-0 obstacle removal on qwen0.6B · WS-1 typed pm-core-shape patch · WS-2 cross-engine agreement · WS-3 masked-attribution prior · WS-4 latent energy oracle | designed |
| V (validation ladder) | V-0 planted ground truth · V-1 matched-null controls · V-2 effect/mechanism split · V-3 cross-cast × cross-proposer replication · V-4 red-team refusal · V-5 advisory calibration audit · V-6 drift re-certification | designed |
| P (paper comparability) | P-1 replicate their released edited checkpoint + mechanical edit audit · P-2 head-to-head same base/budget/suites (+P-2b hygiene variant) · P-3 localization benches from released logs (exp1/2/3; exp7 substituted by P-3b planted sycophant pair) · P-4 optional write-from-scratch MinAtar | artifacts verified live 2026-11-05 |

**Benchmark policy (law):** the paper's suites (MATH-500, GSM8K, IFEval) appear
ONLY in P-arms as comparability. Certification oracles are our frozen G-cells
plus a disjoint held-out generalization battery. Reasons: their practice pools
share distributions with their evals (contamination); mass-scale proposers
Goodhart known suites; obstacle law makes math gains on small casts
impossible, so MATH deltas there measure un-looping, not ability.

## 2. Phases (entry / exit / kill)

### Phase A — harness calibration & ground truth
- **A1 · P-1a mechanical edit audit.** Fetch base `Qwen/Qwen3.5-0.8B` and
  edited `RikiyaT/Qwen3.5-0.8B-weight-space-programming` (Apache 2.0, verified
  present 2026-11-05). Verify the SHA-256 two-tensor claim by streaming tensor
  diff: expect exactly 2 differing tensors (MLP down_proj layers 15 and 19),
  131,072 differing elements. Receipt textual, digest-keyed.
- **A2 · P-1b replication eval.** Frozen harness on base vs edited: MATH-500,
  GSM8K, IFEval, token-limit-hit rate. Compare to their `eval/` raw scores and
  headlines (7.9→48.1 MATH-500; 93%→31% token limit). Verdict replicate /
  non-replicate with NAMED causes (sampler, budget, tokenizer).
- **A3 · V-0 planted ground truth.** K=8 planted obstacles + K=8 null plants
  in qwen0.6B mirrors (rank-1 contrastive directions written into MLP
  down_proj; mechanism known by construction). Blind pipeline: recovery cosine,
  behavioral delta on G2-shaped cells, specificity on nulls. Floors in
  PREREG-A; below floor the program HALTS before any edit claim — the halt is
  a successful verdict of the validation design.
- **A4 · Eval harness freeze.** Scorers (format-invariant, length-normalized
  companions), sampler configs, budgets frozen and digest-keyed.
- Exit: C0 (harness reproduces published numbers within CI) + C1 (measured
  sensitivity/specificity). Kill: A2 non-replication without a named fixable
  cause → harness suspect, downstream arms blocked.

### Phase B — vertical closure
WS-0 → WS-1 → WS-2. Exit: C2 (loop closed end to end; edit is a typed
artifact). Kill clause (ADR 0022 shape): any engine-side concept logic →
integration claim reverts to Proposed.

Addendum 2026-11-06 (WS-2 rescoped by its own live verdict): cross-engine
agreement at tolerance 0 FAILED as measured (27/66 token-id identity on
qwen3-0.6b-bf16; near-tie bf16 argmax convention + 1-ulp kernel drift; eos
padding contract open). Rescope: cross-engine agreement is a REPORTED DRIFT
STATISTIC; the GATE is the certification key law (engine rev in the key ⇒
per-engine re-certification, which V-6 prescribes). WS-2 exit criterion is now:
drift measured, named per cell, and keyed certifications per engine. No
post-hoc tolerance was fitted to the observed receipt; any future tolerance is
a new prereg row evaluated on fresh cells.

### Phase C — false-positive hardening
V-1 (matched nulls: random / shuffled / unrelated-concept / quant-noise; a
passing null halts the pipeline and the halt is the verdict) · V-2 (ablate →
dies, restore → returns, relocate → dies; EFFECT and MECHANISM verdicts
recorded separately) · V-4 (planted format artifacts, length tricks,
battery-gaming edits must be named and refused; refusal rate is a first-class
metric) · P-3/P-3b in parallel (localization benches; planted honest/sycophant
pair via existing LoRA infra instead of rebuilding their excluded 17 GB Gemma
fine-tunes — named non-claim).
Exit: C3 + localization bench numbers. Kill: V-4 refusal rate below floor.

### Phase D — scale & replication
V-3 (≥2 other casts × ≥2 independent proposers; disagreement is data) · WS-3
(top-k agreement with causal find, chance-controlled) · P-2/P-2b (head-to-head
on Qwen3.5-0.8B with 10/25/50 forward-pass budgets and their exp8 practice
pools for protocol equivalence; P-2b disjoint splits MEASURES their
contamination). Exit: C4 + C5. Non-claim: parity is never a pass bar.

### Phase E — economics & drift
V-5/WS-4 (advisory tier per 0007 contract shape: matched-param, memo, n-gram
arms; certificates; measured ROC + evals-skipped-per-false-negative) · V-6
(certification keyed to base digest, tokenizer digest, quant, sampler config,
engine rev; drift outside the key re-runs certification) · battery rotation
epoch 2 · P-4 optional (kill cheap). Exit: C6.

Addendum 2026-11-06b (Phase E state): WS-4 RETIRED on the current denominator
—all five arms AUC 0.5 under FEATURE_ZERO_VARIANCE (the matched-control design
makes every v2 feature constant); the FAIL is a denominator property, not a
latent-prediction verdict; reopen only via a new row (eigen-gap instrument
and/or V-3's varying draws). V-5 = NOT_RUN-SCREENER_RETIRED (both screener
inputs retired/failed; mechanical consequence, reopens with WS-4). V-6 stands:
per-engine re-certification is the gate that WS-2's measured drift justifies.

## 3. Statistical governance (false-positive constitution)

- **Denominator journal**: every proposed direction, run, and named failure
  appended to VERDICTS.md with digests (ADR 0032 predicted-vs-observed).
  Headline format: "3 wins of 400 attempts".
- **Multiplicity**: pre-registered primary contrast per arm; Holm over
  secondary cells; always-valid confidence sequences for sequential
  propose→test direction search (optional stopping priced, not hidden).
- **Blinding**: arm labels shuffled by seeded script (seed frozen in
  PREREG-A); certifier sees IDs only; proposer narratives collected
  separately; unblind only after the verdict file is frozen.
- **Three disjoint probe sets** per edit: localization / certification /
  generalization; overlap is a refuse, not a warning.
- **Keyed certifications**: outside the key = a new claim.
- House laws carried: serial `-j 1` per battery; probe scratch to `$TMPDIR`;
  durable evidence textual; frozen oracles.

## 4. Cost & venue

Local fleet (mlx_native) for A1, A3, B, C, V-*, WS-*; MATH-500-scale evals ≈
0.75M generated tokens per config on 0.8B — trivial for the engine. A2/P-2 use
the hub-cache checkpoints (~3.4 GB total, fetched once). Hosted proposers only
where a local proposer is insufficient, labeled hosted in every receipt,
bounded budget per arm. Exp7 Gemma rebuild: NOT done (non-claim, P-3b
substitutes).

## 5. Cast switchability (standing feature, separate from removal scope)

Qwen3.5-0.8B joins the discovered-cast surface where the Qwen3-0.6B casts live
(`listCachedQwen3Snapshots` over the HF hub cache, mlx_native). Discovery
extends to the `Qwen--` org and `Qwen3.` family prefix. This entry is
independently revertible and survives this package's removal.

## 6. Non-claims (written before any result)

No capability-addition claim. No parity-with-paper pass bar. No claim their
suites are clean (P-2b measures). No localization generalization beyond
measured casts. No exp7 replication claim. A Phase-A halt on specificity is a
verdict of the validation design, not a program failure.

## 7. Risks & pivots

Qwen3.5 architecture support in the Rust engine: verify at A2 setup (config
arch vs supported list); unsupported → cast entry lands blocked with a named
gap, P-arms proceed on the Python boundary path. Their `eval/` raw scores may
lack per-problem granularity → headline ± CI overlap, recorded. Exp3 corpus
rebuild drift → manifest digest check; on drift, exp3 downgrades to
qualitative with a named reason.
