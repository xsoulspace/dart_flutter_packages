# RESULTS-HISTORY.md — every measured result of the lane, in tables

The historical extraction the ledger summarizes. One row per recorded
measurement; the class column uses [`VERDICTS.md`](VERDICTS.md)'s codes
(**F** failed at all · **V-s/V-r** measured wrong, superseded / remeasure owed
· **C** conditional on environment · **O** open · **✓** confirmed).

Standing non-claims that ride every table: **one machine (M1 16 GB), one model,
one corpus, one seed, one split** unless stated; absolute tok/s and wall clocks
are non-claims when the charge current is not real — **the ratio is the
measurement** ([`POWER.md`](POWER.md)); a gate pass is eligibility, never a
product claim. Evidence under `bench/` is gitignored working material; the
tracked binding is [`LINES.md`](LINES.md) + [`MTP-GATES.md`](MTP-GATES.md) +
the ADRs in `docs/decisions/`.

---

## 1. Engine parity & optimization ladder (laya / qwen / lfm2 on the Rust mlx-c host)

| date | measurement | value | gate / threshold | class | evidence |
| ---- | ----------- | ----- | ---------------- | ----- | -------- |
| 2026-10-08 | laya golden on Rust host | 63/63 argmax, prob err 0.0 | exact | ✓ | ADR 0051 |
| 2026-10-08 | laya decision latency | ~90 ms/decision @ ~90-token prompts; submitted-op 2.2 µs | ≤5 ms target RETIRED as folklore | C (device fact) | ADR 0051 |
| 2026-10-09 | R1 mlx.compile A/B (interleaved) | **1.79×** AC (1.21× battery, indicative) | — | ✓ ratio | ADR 0054 |
| 2026-10-09 | R2 qwen3-0.6B-4bit parity | 64/64 greedy tokens + 8/8 tokenizer; decode 54.7 tok/s | token-exact vs python | ✓ | ADR 0054 |
| 2026-10-09 | R3a amortized KV | 2k decode 380 → ~85–120 ms/tok | parity held 64/64 | ✓ | R3 record |
| 2026-10-09 | R3b q8 calibration ladder | full g64 61/63 (0.039) → alt g64 62/63 (0.024) → **alt g32 63/63 (0.0164)** | gate ≤0.02 | F (default) / ✓ (opt-in) | R3b closure |
| 2026-10-09 | R3b q8 latency | no B=1 win — within thermal noise | — | C | `tool/q8_bench.dart` |
| 2026-10-09 | R4 skinny-GEMM MSL kernel | 0.12–0.21× of mlx-c | ≥1.3× | F | R4 gate |
| 2026-10-09 | R4 dequant-GEMV MSL kernel | 0.83–0.98× (1-ulp correct) | ≥1.3× | F | R4 closeout |
| 2026-10-09 | R4 rmsnorm_residual MSL kernel | **1.33×** | ≥1.3× | ✓ (row default-on) | R4 |
| 2026-10-09 | R5 chunked prefill (KV-only chunks) | 2k TTFT 3281 → 1989 ms (−40 %); dropped frames 0–0.3 % | <10 % dropped | ✓ | R5 |
| 2026-10-09 | long-ctx decode "gap" Rust vs python | RETIRED: 2k parity; 4k Rust **0.71–0.75×** (faster) | — | V-s (machine-state artifact) | ADR 0055 P1 |
| 2026-10-09 | KV growth p90 spikes | 34–44 ms at growth steps → `KvCache::reserve` whole-window → gone | — | ✓ fixed | ADR 0055 follow-through |
| 2026-10-09 | LFM2-1.2B rung | 64/64 greedy parity; 49–53 tok/s AC | ≥45 tok/s gate | ✓ | LFM2 rung |
| 2026-10-11 | R6 lfm2-on-plan | decode logits + caches BIT-identical; 64.8 tok/s through the plan; 23/23 op cells | bit-exact | ✓ | R6 record; `plan_op_sweep.rs` |
| 2026-10-11 | LAYA_COMPILE default flip | DECLINED: first traced call 6.6 s; break-even ~150+ decisions/shape | — | C (daemon workloads) | `r1_compile_ab_probe` |
| 2026-10-11 | batch-isolation tolerance sizing | pure batch-size floor **3.6e-4** vs heterogeneous defect **0.86**; contract: decision `==`, distribution 1e-3 | — | ✓ (the precedent) | `laya_native_batch_isolation_test.dart` |
| 2026-10-11 | l0 dispatch perf gate | flapped twice on mid-run battery unplug (610→3102 µs) | 400 µs, AC-only | C (law, never weakened) | ADR 0061 |

## 2. Serving-quality & bench matrix (template + EOS era)

Scorecard format: **chat / decomp / swe / tools** over the three deterministic
lanes; determinism via two same-cast runs ±1.

| date | measurement | value | class | evidence |
| ---- | ----------- | ----- | ----- | -------- |
| 2026-10-09 | 2×2 model×serving matrix | template+EOS DOMINANT: qwen decomp 0→8/10, lfm2 decomp 0→9/10 **within the same model** | ✓ | ADR 0057-era correction |
| 2026-10-09 | fair same-class pair (template+EOS) | qwen0.6B 4/8/1 vs **LFM2-700M 7/10/1** (~80 tok/s) | ✓ | GOAL 10-09c |
| 2026-10-09 | thinking mode at 0.6B | 2/1/0 — hurts | F | fair matrix |
| 2026-10-09 | qwen-1.7B first rows | VOID (garbage from token 0 — rmsnorm `cached[1024]` OOB at cols=2048) | V-s | 796a5a9d-era |
| 2026-10-09 | qwen-1.7B after fix (teacher-forced tie-aware gate) | 64/64; mid pair **qwen1.7B 8/10/3 @ 33–38 tok/s** vs **LFM2.5-1.2B 7/9/3 @ 47–59** | ✓ | same |
| 2026-10-09 | LFM2.5-2.6B row | chat 6/10 · decomp 2/10 · swe 2/5 · tools 5/5 @ 19–33 tok/s — under the 1.2B everywhere | F (not adopted) | ADR 0058 |
| 2026-10-09 | tools lane (3-format checker) | lfm2 5/5, qwen-0.6B 4/5; thresholds pinned lfm2 ≥6/8/2/4, qwen ≥3/7/0/3 | ✓ | ADR 0058 |
| 2026-10-09 | model_bench decode (M1, AC, tok/s fresh/@2k) | qwen0.6B-q4 84.9/67.7 · bf16 38.7/33.7 · 1.7B-q4 44.9/39.2 · LFM2.5-1.2B **70.1/64.3 (flat ctx curve)** | C (absolutes non-claim) | ADR 0056 |

## 3. Parent lane (stage-1 studies, `bench/LINES_PLAN.md`)

| line | measurement | value | gate | class | evidence |
| ---- | ----------- | ----- | ---- | ----- | -------- |
| A | draft-model speculative decode (0.6B→1.7B) | **0.35–1.09×** best | ≥1.3×; physics ceiling k=2 ≈ 1.31–1.58× zero-overhead | F (C: reopens at ≥4:1) | `stage1_specdec/RESULTS.md` |
| A' | native speculative decode (token-exact) | k=2 0.42× · k=3 0.45× · k=4 0.63× · k=6 0.75× | ≥1.5× | F (C: ≥4:1) | spec-decode record |
| B | SSD-paged MoE expert store | parity 8e-5..3.9e-3; **0.33 tok/s** (42.5 % hit, 657 GB read / 96 tok) | ≥15 tok/s @ ≤8 GB | F | `stage1_paged_moe/RESULTS.md` |
| C | route-ahead predictor | 0.4 % one-step route persistence; 0.30 Jaccard | ≥70 % | F | `bench/LINES_PLAN.md` |
| D | sparse-attention device-fit study | defer native DSA/KDA; measure route-prefetch first; one shared gather-attention kernel later | — | ✓ (decision) | `bench/studies/sparse_attention_device_fit.md` |
| E | GLM-5.3-Flash biopsy | 321B / 62 shards byte-exact; 288+1 experts top-8; KDA+DSA hybrid; experts near-Gaussian | — | ✓ (study) | `bench/glm53_biopsy/BIOPSY.md` |
| F | device mesh (weights/KV across M1/phones) | gated off | needs ~50× bytes/token drop | C | `bench/LINES_PLAN.md` |

## 4. MTP — multi-token prediction (Line J / J')

| date | measurement | value | gate | class | evidence |
| ---- | ----------- | ----- | ----- | ----- | -------- |
| 2026-10-20 | OLD arm speedups ("1.41×/1.42×") | lazy-timing artifact (0.95 ms dummy vs 27.18 ms forced = **28.7×**); draft vocab projection (94.5 % of body step) omitted | ≥1.5× | V-s | C-1; `bench/HISTORY.md` |
| 2026-10-20 | OLD arm "nearly flat in k" series (0.688…0.680 ms) | no producing artifact; contradicted 39× by its own forced table | flat ≤1.15 | V-s | C-1 |
| 2026-10-21 | retarget matrix (decode-consistent, held-out) | truth/truth 0.1030 → truth/trunk 0.1182 → trunk/trunk 0.1130 → greedy/trunk/trunk **0.1243** | — | ✓ (instrument) | `RESULTS-mtp-2026-10-21.md` |
| 2026-10-21 | J-G1 acceptance (arm C, held-out) | **0.1235–0.124** (in-sample **0.9015** — memorized) | ≥0.60; trivial bigram 0.1483 | F | C-2 |
| 2026-10-21 | bigram baseline reproduction | 0.1483 → 0.1457 / 0.2330 (pool-dependent); **every pool above every arm** | — | ✓ | EXPERIMENT-PLAN §1.2 |
| 2026-10-21 | copy / constant baselines | recorded 0.0851 / 0.0227; reproduce 0.0384 / 0.0515 under no tried pool | — | **V-r** | C-11 (EXPERIMENT-PLAN numbering) |
| 2026-10-21 | depth acceptance series "0.1393/0.0146/0.0000" | that is a count-3 MODEL, not arm C | — | V-s | C-7 |
| 2026-10-21 | J-G3 original reading | contradicted its artifact (tokens/cycle 1.1393→1.1539→1.1539); gate counted no head cost | — | V-s | C-6 |
| 2026-10-21 | native port token-exactness | 0 divergences; parity fixture bit-exact | exact | ✓ | `qwen_mtp_parity.rs` |
| 2026-10-21 | native speed (interleaved, on battery) | plain 82.0–86.4 tok/s; MTP K=1 **0.47×**, K=2 **0.36×**; mean **0.42×** | ≥1.5× | F | `qwen_mtp_bench` |
| 2026-10-21 | J'-G0 body flatness (forced, projection excluded) | body(8)/body(1) = **2.034 / 2.428 / 2.8–3.5** across runs | NOT-FLAT ≥1.50 | F (physics) | `qwen_marginal_cost` |
| 2026-10-21 | marginal verified position | ~2–4 ms vs ~30 ms AR token (11.9 ms/position on a loaded box — non-baseline) | — | ✓ ratio / C absolute | same |
| 2026-10-21 | instrument wall clock | same prebuilt binary **53 s quiet / 4 m 47 s contended** (93 % of the wait behind other work) | — | C (ratio only) | C-12 (MTP-GATES numbering) |
| 2026-10-21 | arm determinism claim | "reproduced to 4 dp" = one run, two byte-identical copies | — | **V-r** | C-3 |

## 5. LoRA adapters (Line K / K' / K'')

Task pair: perm (disjoint option list) + veto; scored rows 150 (K') then the
full split 293/227 (coverage-complete).

| date | measurement | value | gate / note | class | evidence |
| ---- | ----------- | ----- | ----------- | ----- | -------- |
| 2026-10-21 | K capability, first measure | +0.153 over trivial (python mlx-lm path; substring scorer era) | K-G3 | V-s (superseded below) | `adapter-set-capability-2026-10-21.json` |
| 2026-10-21 | K cross-task collapse first measure | "−0.847", "stopped answering in the label set" | substring scorer: `satisfaction`→fact AND action; `outside_label_set=0` contradicts prose | V-s | C-4 |
| 2026-10-21 | K' strict matrix @150 (base / cond / untagged / permsolo, perm·veto) | 0.4533·0.2400 / 0.8200·0.7733 / **0.8733·0.7800** / 0.9600·**0.1733**; matched trivial 0.5467·0.2733 | strict equality; K'-G1..G6 | ✓ | EXPERIMENT-PLAN §1.0 |
| 2026-10-21 | K''-G1 paired controls (exact McNemar) | tag: perm Δ −0.0533 CI [−0.1219,+0.0153] p=0.185; veto Δ −0.0067 p=1.000. permsolo: perm Δ −0.1400 p<0.001; veto Δ **+0.6000** p<0.001 | — | ✓ (attribution) | `MTP-GATES.md` Part 3 |
| 2026-10-21 | K''-G2 shared union list | 0.7867 perm · 0.7133 veto (+0.24/+0.44 over matched trivial); 9/9 out-of-set = `abstain` on gold `no_grant` (the 6 % leak) | — | ✓ | K''-G2 |
| 2026-10-21 | coverage-complete re-score @293/227 | base 0.4403·0.2511 · cond 0.8328·0.7577 · **untagged 0.8737·0.7533** · permsolo 0.9761·0.1806 · shared 0.8430·0.7004 · fewshot 0.5870·0.3348 · ranked 0.4403·0.2291; matched trivial 0.5598·0.2819 | coverage 1.0000 all cells | ✓ | Row M table |
| 2026-10-21 | L-G1 few-shot | 0.5870 / 0.3348 vs 0.8237 / 0.7033 gates (+0.03/+0.05 over trivial) | PASS would close the line | F | Row M |
| 2026-10-26 | L-G2 noise adapter (random gold labels, seed 1234, all else = untagged) | **0.5392 / 0.2511** vs HIT thresholds 0.7737 / 0.6533 — **MISS both**; veto collapses to one label (`secret_path` 227/227) = base's accuracy to 4 dp; perm below trivial (−0.0205); TIER-0 == TIER-1 to 4 dp; coverage 1.0; trained 420 s on AC 1475 mA | HIT on either task ⇒ format capability | F (format explanation measured out) | `RESULTS-noise-2026-10-26.md`; `adapter-noise-2026-10-26/gates.json` |
| 2026-10-26 | L-G7 third task (perm+instrument-taxonomy pair; corpus 900 rows, disjoint labels+vocab, majority 0.25) | third cell: **shared 1.0000 = untagged 1.0000** (bar 0.95), **leak 0**, completions **204/204 identical**; shared/perm 0.8464 vs untagged/perm 0.9352 (−0.0889, leak-free); base/third 0.2402 (conc 0.990, 2/204 outside-label — the lane's first) | shared ≥ untagged − 0.05 AND leak 0 on third | ✓ (PASS — both pre-registered conditions) | `RESULTS-third-2026-10-26.md`; `adapter-third-2026-10-26/gates.json` |
| 2026-10-21 | L-G6 ranking (two engines) | python 0.4403/0.2291; native 0.4403/0.2819; base emits **0 illegal labels**; native cost ratio 0.93 (perm) / 1.22 (veto) vs generation | PASS would close the line | F | Row M; `rank-bench-2026-10-21.json` |
| 2026-10-21 | L-G6 cross-engine detail | verdicts agree; sum-vs-mean pattern disagrees (native 293/293 rows differ on perm, 0 on veto; python opposite) | — | **V-r** (localize) | Row M gap 8 |
| 2026-10-21 | greedy determinism through mlx_lm | untagged re-score 131/150 = recorded exactly; cond 0.8328 vs 0.8200 | — | ✓ | Row M |
| 2026-10-21 | training / eval / replay costs | arm **995–1084 s** (shared 1338 s); cell eval ~51 s; full gate matrix from cache **2.09 s**; replay scorer 0.183–0.35 s | — | ✓ (ratios) | EXPERIMENT-PLAN §2, B.1 |
| 2026-10-21 | format bridge | mlx-lm artifact: 112 tensors, 56×`lora_a/b`, 0 PEFT names; `load_auto` detects + refuses ambiguity; trained artifact loads+merges (27 lib + 8 swap + 1 artifact tests, 0 fail) | K-G1/G2/G4 | ✓ | C-13; `tests/mlx_lm_artifact_merge.rs` |
| 2026-10-21 | quantized-base merge refusal | ‖ΔW‖/‖W‖ median 5.0 % ≈ requant error → refuse at bind is correct | — | ✓ | K-G4 |
| 2026-10-21 | swap surface | byte-reversible; digest cache key; epoch increments | K-G1/G2 | ✓ | `tests/lora_set_swap.rs` 8/8 |

## 6. Acceleration program (Row M, L-G4)

| date | measurement | value | gate | class | evidence |
| ---- | ----------- | ----- | ----- | ----- | -------- |
| 2026-10-21 | lockstep control (concurrency 1→16) | aggregate tok/s 80.89 → 81.04 (ratio 0.996–1.002) | flat = measurement is stable | ✓ | `RESULTS-acceleration` §1 |
| 2026-10-21 | projected fused whole-step ratio | batch 2 **1.91×** · 4 **3.66×** · 8 **5.39×** · 16 **9.95×** | ≥1.5 at concurrency 8 | ✓ lever / **V-r** (not measured through a fused path) | same |
| 2026-10-21 | body GEMM vs tied projection scaling | body 1.92→2.67 ms (1→8, near flat); 77.8 MB projection grows 3.6×; tied projection = **94.5 %** of a bf16 body step (311 MB table) | — | ✓ | §1; `RESULTS-mtp` §0.2 |
| 2026-10-21 | bit-level batch divergence | max abs diff 0.0625 (body GEMM) / 0.0239 (projection); **same-shape-class control diverges too** | bit-identity — RETIRED as the wrong bar | V-s → replaced by decision-invariance gate | §1.5–1.6 |
| 2026-10-21 | fused-forward existence | `qwen.rs` hardcodes the batch dim to 1 — does not exist | four-part change named | O | Row M non-claims |

## 7. Nursery / tiny models trained from scratch (Line I)

| date | measurement | value | gate | class | evidence |
| ---- | ----------- | ----- | ---- | ----- | -------- |
| 2026-10-18 | smoke-run gates (expected untrained) | G2 0.128 · G3 0.167 | instrument check | ✓ | `bench/nursery/runs/smoke/` |
| 2026-10-18 | RUNG-0 (3.5M, 2000 steps = 1 epoch) | G2 **0.281** (0.128@3steps → 0.281 vs random 0.036) · G3 **0.807** · G1 pole definition invalidated by one-bit routing (amended for the next rung) · G4 **PASS** (0.42 MB/token packed 4-bit) | G2 ≥0.70, G3 ≥0.90 | F (with data: decision head stands WITHOUT MoE; margins noise-stable, p50 7–16 vs 30B's 1e-3) | `bench/HISTORY.md` 2026-10-18 |
| 2026-10-18 | routing_window=128 A/B | set-equality **0.9996**; G3 0.860 vs control 0.851; CE 3.337 vs 3.451; GATE-1 poles 19/32 | G2 pass = BY CONSTRUCTION, not learned | ✓ pass / F thesis | `TRAIN-GATES.md` reading note |
| 2026-10-18 | scale replication (12× capacity) | moves NOTHING the gates measure | — | F | `bench/HISTORY.md` |
| 2026-10-18 | PERM-GATE-1 (attempt 4) | does not beat all-abstain on the gate's terms (unsafe > 0) | — | F so far; all-abstain stands as shipped behavior + data collector | `bench/HISTORY.md` |
| 2026-10-18 | trainer NaN lesson | lr 3e-3 diverged mid-run; overwrite-style checkpoint carried the poison → rotate checkpoints; v2 lr 1e-3 survived 2,428 pathological batches, loss 0.54 | — | ✓ (lesson) | `bench/HISTORY.md` |
| 2026-10-18 | emergent persistence at scale | ~0.34 plateau at 3.5M and 43M; 0.4 % at 30B | ≥0.70 | F | `TRAIN-GATES.md` |

## 8. Seed & contract carriers

| date | measurement | value | class | evidence |
| ---- | ----------- | ----- | ----- | -------- |
| 2026-10-21 | provider seed-forwarding reading (ADR 0071, named time 21:31) | two providers forward on the wire; two refuse with an echo; local mlx_native path was the violator (closed by concurrent change) | ✓ (reading, not a tree claim) | ADR 0071 |
| 2026-10-25 | seed carrier committed | SplitMix64 counter-based RNG (draw = f(seed, position, stream)); golden + honesty suites across core/anthropic/openai/openrouter/mlx_native | ✓ | `fa2b66f1` |
| 2026-10-26 | core suite re-run | 159/159 pass (incl. seeded_rng golden 286-line, seed honesty, seed validation) | ✓ | verified this session |

## 9. The lane's own meta-results (what measuring costs)

| measurement | value | class | evidence |
| ----------- | ----- | ----- | -------- |
| lazy-MLX timing error | same op 0.95 ms (dummy eval) vs 27.18 ms (forced) = **28.7×** | ✓ law | `bench/HISTORY.md`; AGENTS.md laws |
| wall-clock load sensitivity | same prebuilt binary 53 s quiet / 4 m 47 s contended (19.5 s CPU in 287 s wall) | ✓ ratio-only law | C-12 |
| battery throttling | sustained GPU AND CPU 4–10× (decode 45→3.5 tok/s) | ✓ law | `POWER.md`; ADR 0061 |
| scoring-question cost after caching | ~6,000× cheaper than a training arm (0.183 s vs 995 s) | ✓ | EXPERIMENT-PLAN B.1 |
| substring-scorer blast radius | one defect class produced both the −0.847 collapse and the think-echo defect | ✓ lesson | C-4; META-LESSONS |
| record ID collision | C-11/C-12 double-assigned across `EXPERIMENT-PLAN.md` and `MTP-GATES.md` | ✓ noted | `VERDICTS.md` hygiene note |
