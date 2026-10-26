# VERDICTS.md — what failed at all, what was measured wrong, what can reopen, what is open

One screen. This is the **classification layer** over the lane's record. The
row-level authority stays [`LINES.md`](LINES.md); the frozen thresholds stay
[`MTP-GATES.md`](MTP-GATES.md) and [`TRAIN-GATES.md`](TRAIN-GATES.md); the
costs and orders stay [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md); every
measured number is tabulated in [`RESULTS-HISTORY.md`](RESULTS-HISTORY.md).
This file answers one question a reader otherwise has to reconstruct from 2,000
lines: **which verdicts are final, which numbers are void, which closures are
environment-conditional, and what is actually next.**

This file is **a reading of the record at a named time** — 2026-10-26 (last
touch: the L-G2 noise arm, branch `ag-c` after `03720365`) — not a claim about
the tree today. If a row here and its evidence disagree, the evidence wins and
this file is wrong; fix it here.

Reading order: **this file → [`LINES.md`](LINES.md) rows →
[`MTP-GATES.md`](MTP-GATES.md) gates → `bench/nursery/experiments/RESULTS-*`
(gitignored working material).**

---

## The four classes

| code | meaning | what reopens it |
| ---- | ------- | --------------- |
| **F** | **FAILED at all.** The verdict is real on the evidence class that produced it. A rerun never reopens it — only a **new evidence class** (new arm shape, new hardware class, new scale, new corpus property), registered as a new arm with a frozen threshold *before* it runs. | a new registered arm |
| **V** | **MEASURED WRONG.** The recorded number (or the reason quoted for it) was an artifact — lazy timing, substring scorer, token-accounting mismatch, conflated arms, one-run-two-copies. The number is void and must never be cited. Two sub-states: **V-s** (superseded — a corrected number exists in the record) and **V-r** (remeasure owed — no corrected number exists yet). | the named correction / remeasure |
| **C** | **CONDITIONAL.** Closed on *this* device / config / corpus pair. The reopen condition is named below and is a **fact about the environment** (hardware, model ratio, power state, workload shape), not a tuning knob. Re-opening still requires the condition to be measured and a new frozen gate. | the named condition, measured |
| **O** | **OPEN.** Never run or never built. The gate and cost are named. | running the arm |

---

## The path forward (what is actually next)

Ordered by the lane's own law — *an arm that can close or unlock the line runs
before an arm that can only refine it* — and by measured cost.

**Tier A — the one lever (engineering, no training).**

1. **Build the fused batched decode** — the four-part `qwen.rs` change (batch
   dim from `tokens.dim(0)`, cache allocated with it, per-sequence offset or
   pad+mask, expose the tied embedding). Gate: **decision-level invariance + no
   short-row defect on the left-padded path** (the reformulated L-G4
   precondition; the tolerance method already exists in
   `test/laya_native_batch_isolation_test.dart`). Payoff if it holds: the
   projected **5.39× at batch 8** becomes a measured number, **and the ranking
   idea flips on cost** — ranking loses today only because labels cannot batch
   (native 0.93–1.22× vs generation). If it fails, it is a device fact and the
   batching lane closes the way MTP did.

**Tier B — the cheap closers and refiners (minutes to ~1.5 h).**

2. **L-G2 noise adapter — RUN 2026-10-26, MISS on both tasks.** The
   pre-registered prediction fired exactly: 0.5392 vs a 0.7737 threshold
   (perm), 0.2511 vs 0.6533 (veto), coverage 1.0 both, TIER-0 == TIER-1 to
   4 dp. On veto the noise adapter emits ONE label (227/227) and equals
   base's accuracy to 4 dp; on perm it lands below trivial. The format
   explanation of the adapter's gain is measured out. Evidence:
   `bench/nursery/experiments/RESULTS-noise-2026-10-26.md`.
3. **L-G7 third task** (~1.5 h; corpus generated, 900 rows, disjoint,
   majority 0.25) — settles the shared-answer-space rule (per-task always vs
   conditional-default). Leak > 0 on a dissimilar pair also voids the
   upper-bound reading of the 6 % perm/veto leak.
4. **L-G5 prompt-shape cost bench** (inference-only) — the product number for
   shared vs per-task option list (bytes, prefill wall, KV, cache hit rate).
5. **Rank with the adapter** (inference-only, minutes; never measured) —
   the record's own line is "the adapter changes the ranking, not the output
   format" (ranked(base) == base). ranked(adapter) turns decode-bound
   evaluation into prefill-bound scoring and, with Tier A done, is the
   "model as ranker over a closed vocabulary" product measurement.

**Tier C — record repairs, all CPU/Tier-0 (owed before the affected numbers
are gate inputs again).**

6. **Localize the L-G6 cross-implementation disagreement** — both engines agree
   on the FAIL verdict but disagree on the sum-vs-mean pattern (native: 293/293
   rows differ on perm, 0 on veto; Python: the opposite). Suspects: prompt
   rendering, generation cap. Until localized, neither implementation is a
   clean gate input for a *re*-run.
7. **Prove arm determinism** (the C-3 void) — run one training arm twice,
   distinct timestamps, compare artifacts. One run.
8. **Native-surface capability number** — the Rust engine can load and merge
   the trained artifact (C-13 closed) but has never produced the scored
   completions; the +0.31/+0.47 is still a python-path number.
9. **Seed determinism end-to-end** — ADR 0071's counter-based sampler is
   implemented in core with golden tests, but no test asserts a seeded local
   decode reproduces through `MlxNativeTextClient`.

**Then, not before:** RUNG-1 of the nursery (PERM-GATE-1 — the decision head
into laya's real slot; it stands without the MoE thesis), and any MTP-shaped
arm on new hardware (must be a new registered arm; see CONDITIONAL).

---

## FAILED at all (F) — real verdicts

| verdict | measured why | what a reopening arm would need (new evidence class) | evidence |
| ------- | ------------ | ---------------------------------------------------- | -------- |
| Few-shot control (L-G1): base + 8 exemplars does not match the adapter | 0.5870 / 0.3348 vs 0.8237 / 0.7033 gates — exemplars buy +0.03/+0.05; they teach answer variation, not the decision | a different exemplar budget or retrieval scheme = a new arm with a new threshold (the non-claim already says this FAIL is not a product decision) | `LINES.md` Row M; `RESULTS-acceleration-2026-10-21` |
| Ranking the base's labels (L-G6): base ranks, wrongly | ranked(base) == base on perm (0.4403 = 0.4403); within 0.03 on veto — a DECISION failure, 0 illegal labels emitted, in two engines | ranked(**adapter**) — a different arm, now OPEN (Tier B-5) | `LINES.md` Row M; `rank-bench-2026-10-21.json` |
| The `Task:` tag as conditioning (K''-G1) | paired vs untagged control: perm Δ −0.0533 p=0.185, veto Δ −0.0067 p=1.000; both point estimates negative | a larger n (this control cannot resolve below ~±0.06–0.12) — but "unproven-harmful", not "proven-harmful"; not worth an arm | `MTP-GATES.md` Part 3 |
| A SET of swappable task specialists | a single-task adapter damages the unseen task **below trivial** (permsolo veto 0.1806/0.1733 vs 0.2733/0.2819 baseline, p<0.001) — interference is the adapter's unconditional prior | per-task adapters on SEPARATE resident bases = different product, no swap surface | `LINES.md` Row K; K''-G1 table |
| Emergent MoE route persistence (Line I thesis) | plateaued ~0.34 at 3.5M and 43M params; 0.4 % at 30B; only `routing_window>1` candidates pass (by construction) | a per-token-routed candidate at a new scale that passes GATE-2 honestly — the thesis question, not a rerun | `TRAIN-GATES.md`; `bench/HISTORY.md` 2026-10-18 |
| Paged-MoE expert store on 16 GB (Line B) | parity held (8e-5..3.9e-3) but 42.5 % hit rate → 0.33 tok/s vs ≥15 gate (I/O-bound, 657 GB read / 96 tok) | a model whose bytes/token drops ~50× (same condition as Line F) | `stage1_paged_moe/RESULTS.md`; `bench/LINES_PLAN.md` |
| Route-ahead prefetch predictor (Line C) | 0.4 % one-step route persistence, 0.30 Jaccard vs ≥70 % gate — no locality to prefetch against | a model with persistent routing (Line I's window trick changes the premise, not this verdict) | `bench/LINES_PLAN.md` row C |
| LFM2.5-2.6B as the production cast | under the 1.2B on every lane (chat 6/10, decomp 2/10, swe 2/5) at 19–33 tok/s with 8–33 s thinking walls | a new checkpoint generation, measured — recorded, NOT adopted stands | ADR 0058 evidence; `pure-rust` lane record |
| Thinking mode at 0.6B | 2/1/0 with enable_thinking=true — hurts at this scale | a bigger trunk | fair-matrix record, ADR 0057 era |
| Bit-identity as the batch-precondition bar | the same-shape-class control diverges too — the batch dim moves the bits; fp16 trunks cannot deliver it | none — the bar itself is retired; its replacement (decision-level invariance) is the standing gate | `MTP-GATES.md` Part 4 post-run note |
| The swappable-set product shape (`lora_set.rs` as shipped intent) | set not justified (see F above); the surface is kept only as a cheap-to-re-derive negative | a product that genuinely swaps adapters per request on non-quantized bases | `LINES.md` Row K |

---

## MEASURED WRONG (V) — the void register

### V-s — superseded: a corrected number exists; never cite the old one

| the record said | the defect | corrected state | evidence |
| --------------- | ---------- | --------------- | -------- |
| MTP old arm "1.41×/1.42× speedup"; "python timings a lower bound" | lazy-MLX timing: dummy eval measured graph construction — same op 0.95 ms vs 27.18 ms (**28.7×**); draft's own vocab projection (94.5 % of a body step) omitted from the cost model | native interleaved: plain 82–86 tok/s vs MTP **0.42×** (K=1 0.47×, K=2 0.36×) | `bench/HISTORY.md` 2026-10-21; C-1 |
| MTP "the batched trunk forward is nearly flat in k" (0.688/0.682/…/0.680 ms) | no producing artifact in the tree; contradicted 39× by the same document's forced table | body(8)/body(1) = **2.0–3.5** (three runs: 2.8–3.5, 2.428, 2.034) → NOT FLAT, Line J closed on physics | C-1; `qwen_marginal_cost` |
| MTP count line "J-G3 FAILS: no count beats count 1" | contradicted its own artifact (tokens/cycle 1.1393 → 1.1539 → 1.1539 names count 2) and counted no head cost | count line closes via C-5 accounting + J'-G0 physics instead — same verdict, corrected reason | C-5, C-6 |
| depth acceptance 0.1393/0.0146/0.0000 as "arm C" | that series is a count-3 model (loss sums three depths, 13.44 vs 0.46) — two models conflated | arm C at count 1: 0.1235; depth series for count 1 not re-derived (does not matter post-closure) | C-7 |
| adapter cross-task collapse "−0.847", "stopped answering in the label set at all" | substring scorer: `satisfaction` matched `fact` AND `action`; `outside_label_set=0` contradicts the prose | strict scorer, non-degenerate task: collapse reproduced at **−0.100** below trivial (0.1733 vs 0.2733, p<0.001) — direction real, magnitude was artifact | C-4; EXPERIMENT-PLAN §4.1 |
| adapter capability "+0.153" | measured on the python mlx-lm runtime path; the Rust surface could not even load that format then | strict, matched-baseline: **+0.31 perm / +0.47 veto** over trivial; native surface can now load+merge (scored completions still owed — see V-r) | C-10, C-13; `LINES.md` Row K |
| "arm matrix run twice, reproduced to 4 decimal places" | **one run, two copies** (byte-identical timestamps) | superseded by an explicit non-claim: arm determinism unproven → V-r below | C-3 |
| the 3–4× long-context decode gap (Rust vs python) | machine-state artifact, not an implementation gap | interleaved: 2k parity, 4k Rust **faster** 0.71–0.75×; gap retired | ADR 0055 P1 |
| qwen-1.7B rows (0/0/0, "garbage from token 0") | `rmsnorm_residual.metal` hardcoded `threadgroup float cached[1024]` → OOB at cols=2048 → NaN from L4 | fixed; teacher-forced tie-aware gate 64/64; mid pair now VALID (qwen1.7B 8/10/3 vs LFM2.5 7/9/3) | 796a5a9d-era record |
| old python-recorded laya fixture (4/63 disagreements) | upstream MLX kernel drift, not a lane defect (Swift dylib bit-identical to Rust; python mirror agreed) | oracle regenerated (`regenerate_golden.dart`); 63/63 @ 0.0 stands | ADR 0051 evidence |
| "12 held-out prompts × 192 = 2160 positions" | the artifact says 12 × 191 = **2292** | cite the artifact | C-8 |
| `accept_teacher` as an independent number | provably identical to `accept_self` at count 1 | one number | C-9 |

### V-r — remeasure owed: no corrected number exists yet

| void number | why it is void | what the remeasure is | blocks |
| ----------- | -------------- | --------------------- | ------ |
| MTP `copy` 0.0851 / `constant` 0.0227 trivial baselines | do not reproduce under any of 16 pool×eval combinations (reproduced: 0.0384 / 0.0515, pool-dependent); both erred in the direction that flattered the arms | re-derive with a pinned pool definition (the recorded one is unrecoverable from the tree) | nothing load-bearing — bigram (the closure's baseline) reproduces (0.1483 → 0.1457/0.2330) |
| Arm determinism (any training arm) | the only "reproduction" was one run copied twice | run one arm twice, distinct timestamps, compare artifacts byte-wise | any future claim that an arm matrix replicates |
| L-G6 sum-vs-mean pattern across engines | native: 293/293 rows differ on perm, 0 on veto; python the opposite — same corpus file | localize (prompt rendering vs generation cap), then one deliberate cross-read | a clean L-G6 re-run; the FAIL verdict itself is F-class and stands |
| Native-surface adapter capability | the +0.31/+0.47 came from the python runtime path; the native path loads+merges but has never scored | score the cached prompts through the Rust engine | any product claim about adapter capability on the shipping surface |
| L-G4 projected ratios (1.91/3.66/5.39/9.95×) | projected from an amortization probe; the fused forward does not exist; numbers measured through a fused path are not gate inputs until decision-invariance + no-short-row hold | build the fused path (Tier A) and measure through it | any fused-batch throughput claim |
| Template-era absolute tok/s and wall clocks (all rows) | battery/charge-current holes; the same binary runs 53 s quiet / 4 m 47 s loaded | none — permanent: **ratios are the measurement** (POWER.md law, not a debt) | nothing; quoted as non-claims |

---

## CONDITIONAL (C) — closed here; the reopen condition is named

| verdict | closed on | reopen condition (measured, not tuned) | evidence |
| ------- | --------- | -------------------------------------- | -------- |
| MTP as speed | M1 16 GB: body(8)/body(1) = 2.0–3.5 vs 1.50 NOT-FLAT gate; port commits ≤1 token/round at K=1 | (a) hardware where the body forward is genuinely flat (≤1.15) or the tied projection is far cheaper; (b) a **pretrained** DeepInfer-shaped head (noise init, markov embedding, confidence head, multi-layer features) — registered as a NEW arm with a frozen threshold. The acceptance number (0.124 held-out) stays useful | `LINES.md` Row J; `MTP-GATES.md` Part 2 + DeepInfer section |
| Draft-model speculative decode | 0.35–1.09× (stage1) and 0.42–0.75× (native) at 1:2.8 target:draft; physics ceiling k=2 ≈ 1.31–1.58× zero-overhead | a ≥4:1 target:draft pair (8B-class + 1.2B draft) + an acceptance probe first | `bench/LINES_PLAN.md` row A; spec-decode record |
| Device mesh across M1/phones (Line F) | gated off: needs ~50× bytes/token drop for the measured models | a model class whose bytes/token drops ~50× | `bench/LINES_PLAN.md` row F |
| `LAYA_COMPILE` as default | first traced call 6.6 s; break-even ~150+ decisions per shape; steady 1.79× AC | daemon-class long-lived workloads on one shape | `LINES.md` R6 record; `r1_compile_ab_probe` |
| q8 (LAYA_Q8) as default | calibration green ONLY at alternate-layers g32 (63/63 @ 0.0164); no B=1 latency win (compute-bound) | products that need resident-weight bytes; a score/noul sensitivity pass per new checkpoint | R3b closure record |
| Perf gates asserting | battery throttles 4–10×; l0 flapped twice on mid-run unplug | AC (the gate law itself: battery = POWER-CONTAMINATED banner + pass; unknown keeps asserting) | `POWER.md`; ADR 0061 |
| Shared answer space across tasks | cost −7–9 points + 6 % foreign-label leak — but perm+veto are BOTH permission requests, so the leak is an **upper bound** | L-G7: a third, semantically dissimilar task (leak 0 AND ≤0.05 loss ⇒ legal for dissimilar groups; leak > 0 ⇒ per-task always) | K''-G2; `MTP-GATES.md` L-G7 |
| Fused-batch numbers as gate inputs | the fused forward does not exist; bit-level divergence (0.0625 body / 0.0239 projection) is measured and reported, never hidden | decision-level invariance + no short-row defect on the left-padded path (Tier A) | `MTP-GATES.md` L-G4 post-run note |
| Speculative/MTP native ports as shippable decoders | token-exact but 0.42×/0.36× on this device | same conditions as their parent rows | `qwen_spec_bench`/`qwen_mtp_bench` records |

---

## OPEN (O) — never run or never built

| item | gate | cost | pre-registered expectation |
| ---- | ---- | ---- | -------------------------- |
| Fused batched decode (the four-part change) | decision invariance + no short-row | engineering, no training | 5.39× projected at batch 8; flips ranking economics |
| L-G7 third task | shared ≥ untagged − 0.05 AND leak 0 | ~1.5 h (corpus ready) | three-case reading frozen in `MTP-GATES.md` |
| L-G5 prompt-shape cost | shared ≤ 10 % prefill wall AND 0 added bytes | inference-only | cost gate, independent of accuracy |
| ranked(adapter) | compare vs generation accuracy + prefill-bound cost | minutes | unnamed by any gate yet — would need a frozen threshold before it counts |
| Constrained decoding / logit masking | probe: base outside-label-set rate | minutes | predicted dead on arrival — the base already emits 0 illegal labels (L-G6) |
| Seed determinism E2E test | seeded local decode reproduces via `MlxNativeTextClient` | small | contract exists (ADR 0071); enforcement does not |
| Nursery RUNG-1 (decision head → laya's slot) | PERM-GATE-1 | one training rung | stands WITHOUT the MoE thesis (margins noise-stable) |
| MTP attention head | none — J'-G4 does not buy it | not bought | eligible only if flat-forward hardware appears AND a head passes J'-G1 on it |
| Tracked fixture for the adapter-format gate | make `mlx_lm_artifact_merge` runnable on a clone | small | closes the "gate that cannot run on a clone" gap (EXPERIMENT-PLAN §5.3) |
| CI of any kind | — | — | the repo has no workflow directory; every number is produced by hand |

---

## CONFIRMED (✓) — standing results, for contrast

| result | number | evidence |
| ------ | ------ | -------- |
| LoRA adapter capability (one adapter, both tasks, untagged) | +0.31 perm / +0.47 veto over matched trivial; coverage 1.0; strict scoring; reproduced 131/150 on re-score | `LINES.md` Row K/Row M |
| The gain is NOT format (L-G2, 2026-10-26) | noise adapter (random labels, all else equal) 0.5392 / 0.2511 vs thresholds 0.7737 / 0.6533 — MISS both; veto collapses to one majority label = +0.000 over trivial; TIER-0 == TIER-1 to 4 dp | `RESULTS-noise-2026-10-26`; `adapter-noise-2026-10-26/gates.json` |
| Attribution: multi-task data load-bearing; tag not; option list = refinement (+7–9 pts, prevents the leak) | permsolo p<0.001 both directions; tag p=0.185/1.000; shared still transfers | K''-G1/G2 |
| LoRA mechanical surface | byte-reversible swap; digest cache key; quantized base refused; mlx-lm↔PEFT auto-detect; artifact merges in-suite (27+8+1 tests) | `lora_set.rs`, `lora.rs`, `tests/mlx_lm_artifact_merge.rs` |
| Prefix-cache weight identity | engine-owned digest; stale hit impossible; test-locked | Row L |
| Batched-decode lever is worth buying | lockstep control flat 0.996–1.002 across 16×; projected 5.39× @ 8 | `RESULTS-acceleration-2026-10-21` §1 |
| Batch-isolation tolerance method (the precedent) | pure batch-size floor 3.6e-4 vs heterogeneous defect 0.86; decision `==`, distribution 1e-3 | `laya_native_batch_isolation_test.dart` |
| Seed contract carrier | ADR 0071; SplitMix64 counter-based RNG; honesty echo on 4 providers; core 159/159 green (2026-10-26) | ADR 0071; `seeded_rng.dart` |
| Template + EOS is the dominant serving factor | decompression 0→8/10 (qwen) and 0→9/10 (lfm2) WITHIN the same model | 2×2 matrix, ADR 0057 era |
| Engine parity spine | laya 63/63 @ 0.0 / 1.5e-8; qwen+lfm2 plan-tree bit-identical; plan_op_sweep 23 cells | `test_fresh.sh`; R6 record |
| Replay infrastructure | every gate question from cached completions, 0.183–0.35 s, no GPU; one scoring definition (`tool/nursery/scoring.py`) | EXPERIMENT-PLAN §2, §3 |
| Instruments that paid | `qwen_marginal_cost` (53 s closed Line J), forced-eval law (28.7×), interleaved A/B, Tier-0/Tier-1 split | Row J; `PYTHON-BOUNDARY.md` |

---

## Record-hygiene note

The correction IDs **C-11 and C-12 are double-assigned** across the two record
files: `EXPERIMENT-PLAN.md` uses C-11 (copy/constant baselines) and C-12
(baseline sample-set mismatch), while `MTP-GATES.md` Part 3 uses C-11 (the
gate-contrast defect) and C-12 (the budget correction). Cite corrections by
**description + file**, never by number alone. This note does not renumber
anything — the numbers are frozen where they were written.

## Non-claims

- Every number behind these classes is **one machine (M1 16 GB), one model
  (Qwen3-0.6B-4bit unless stated), one corpus, one seed, one split**, per the
  standing non-claims in `LINES.md`.
- A gate pass is **eligibility, never a product claim**.
- This file classifies; it does not weaken, waive, or renumber any frozen
  threshold. Where it and the evidence disagree, the evidence wins.
