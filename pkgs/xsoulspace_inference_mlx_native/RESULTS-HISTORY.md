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
| 2026-10-26 | Tier A fused batch (built) + decode sweep | fused 1.55/1.75/**1.93**/3.19× aggregate at B=2/4/8/16 (AC baseline, 95.0→303.0 tok/s); lockstep control flat 0.987–1.021; gate: labels exact across solo/B8/B16, co-batch drift 0.0, solo-join floor 0.071 (< 0.15 frozen), positive control 0.60; fused rank 0.80× of sequential at K=4, 1.03× at K=2 | ≥ 1.5 at c=8 | ✓ (lever bought; 5.39× projection retired) | `RESULTS-fused-tier-a-2026-10-26.md` |
| 2026-10-26 | L-G5 prompt-shape cost | shared +22 tok/+96 B per request; cold prefill +55 % (60.9 vs 39.2 ms c1; 40.3 vs 26.7 ms c8 batched); KV 114,688 B/tok/seq; prefix cache at 2048+ window: per-task **0 % hit**, shared **100 % from request 2** (2168/2169; 32–43 ms vs ~1880 ms = 57×) | ≤ 10 % wall AND 0 added bytes | F (fails frozen; warm-cache recovery measured = conditional) | `RESULTS-fused-tier-a-2026-10-26.md` §L-G5 |
| 2026-10-26 | arm determinism (C-3, two identical noise-arm runs) | adapter sha256 differs; scores perm 0.5597/0.4505, veto 0.2819/0.2247 — a ±0.05–0.11 run-to-run band; per-item agreement 15/293 | margins > band are stable | ✓ (C-3 resolved: NOT run-deterministic; L-G2 MISS stable) | `RESULTS-tier-c-repairs-2026-10-26.md` §1 |
| 2026-10-26 | L-G6 native scorer corrected (two bugs) | missing max add-back in the stable lse + probability-vs-logprob eos comparison; corrected native perm 0.4403 == python exactly; veto 0.3128 vs 0.2291 residual; eos_dominant 293+227 → 0 | — | **V-s** (native L-G6 numbers superseded) | `RESULTS-tier-c-repairs-2026-10-26.md` §3 |
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

## 10. 2026-10-27 — the native surface carries the adapter (mostly); the ranker product is viable

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| Runtime-LoRA surface | `Qwen3::attach_lora`: 56/56 targets validated, unknown targets refuse, logits MOVE, identity folds the digest, plan mode refused under an adapter | ✓ gate | `tests/qwen_runtime_lora.rs` |
| N-G1 native capability | perm 0.8976 (bar 0.8237 — native ABOVE python's 0.8737) / veto 0.6828 (bar 0.7033 — −0.02 past the margin); coverage 1.0, leak 0; +0.3379/+0.4009 over matched trivial | F/C split at the frozen terms | `RESULTS-native-surface-2026-10-27.md` |
| R-G1 the ranker product | ranked(adapter) vs generated(adapter): perm 0.8942 vs 0.8976, veto 0.6916 vs 0.6828 — PASS both; 0 illegal labels by construction | ✓ | same |
| L-G6 veto residual localized | tokenization identical (0/908); per-label sums differ median 0.27 nats (bf16-vs-fp16 class); all 91 argmax flips are the near-tied secret_path/no_grant pair; sum-norm agrees 80 % | ✓ localization | same |
| Cross-engine reproduction | python re-derived 2026-10-27 == recorded cells exactly (0.2291 veto); two native binaries agree exactly on generation (263/293; 0.6828) | ✓ | same |
| Pre-existing red recorded | `mlx_native_lazy_client_test` thinking-truncation test red at the pre-session tree too (stash-proven); disposition owed before CI green | noted | this session |

Non-claims: battery-powered run (24–26 %, 0 mA) — all wall clocks and cost
ratios on 2026-10-27 artifacts are non-claims; the runtime-LoRA surface runs
the imperative path (no plan/fused claims under an adapter); one adapter, one
machine.

## 11. 2026-10-27 (later) — the fused batch at the wire: the lever is a product surface

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| W-G1 decision answers byte-equal at the wire | 6 heterogeneous classification prompts, concurrent, coalescing window 300 ms: every wire payload == its solo-path answer | ✓ gate (frozen before the run) | `RESULTS-wire-batch-2026-10-27.md` |
| W-G2 the batch actually formed | batchRuns ≥ 1, lastBatchSize ≥ 2, batchedRows 6/6, soloFallbackRows 0 | ✓ gate | same |
| W-G3 a lone request is untouched | size-1 window routes solo; answer == coalescing-OFF server | ✓ gate | same |
| Free-form agreement probe | this run agreed; run-dependent by the engine gate's tie-flip measurement — reported, never gated | noted | same |
| The CI-blocking red disposed | thinking test budget 128 → 768 (prompt's measured thinking length exceeds 128); assertion set unchanged; battery 42 pass / 1 skip / 0 fail | ✓ test-budget repair | same |

Built: `mlx_native_qwen_generate_batched` FFI (+ api-version probe),
`NativeQwenTextEngine.generateBatch/Async`, opt-in coalescing in
`LayaQwenChatServer` (admission rises with the window; default server
byte-identical to pre-change), `serve_text --coalesce-ms/--max-batch`.
Non-claims: one base model, one machine, battery power (decision arms
only); fused ≠ bit-identical to solo; coalescing default stays OFF for
free-form traffic — the owner flip is informed by this evidence, not
made by it.

## 12. 2026-10-27 (latest) — the format gate runs on every clone; the workflow found its live path

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| Tracked format fixture (EXPERIMENT-PLAN §5.3) | synthetic mlx-lm adapter built in-test at the TRUE on-disk orientation, known dyadic values: transpose verified by VALUE, merge delta `1 + scale·B@A` exact, apply_to full, missing-target/unmatched-lora_a/no-LoRA-tensors refusals — 2/2 gates green locally | ✓ gate | `tests/mlx_lm_artifact_merge.rs` (new second test) |
| Workflow location law | `.github/archite_workflows/` is DEAD to GitHub Actions (only `.github/workflows/` is read) — the gate file had never triggered a run; moved to the live path, trigger extended to `ag-c` pushes | ✓ paid-for lesson | `.github/workflows/mlx_native_gate.yml` header |

Owner-facing note (recorded, not acted on): the repo's other three workflow
files still sit in the dead `archite_workflows/` directory; their runs
stopped when they left `.github/workflows/` (last: 2026-03-30). Restoring
them is the owner's call.

## 13. 2026-10-27 (final) — the first real CI run named the clean-clone truth

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| The workflow RAN (first time ever) | run 40486026348 on ag-c; both legs failed fast on environment, zero lane regressions | ✓ run observed | `.github/workflows/mlx_native_gate.yml` |
| DART leg blocker | root pubspec `dependency_overrides` point whole families (ecsly/intentcall/universal_*) at machine-private checkouts (absolute `/Users/antonio/...`); `resolution: workspace` makes every package's pub get resolve the root ⇒ `flutter pub get` fails on ANY clone | owner decision (publish or vendor) | run log; root `pubspec.yaml` |
| NATIVE leg blocker | `cargo test` needs machine-local cmake MLX/mlxc static libs (build.rs refuses loudly); the real test gate stays local on AC | ✓ by design | `build.rs`; ADR 0061 |
| CI scope re-set | workflow now runs the honest compile gate: `cargo check --release --all-targets` against named stub artifact dirs on macos-14 | ✓ re-scoped | the workflow file |

Local gates at close: merge gates 2/2 (trained artifact + new synthetic
format fixture), Dart battery 42/1 skip/0 fail, native suite green.

| 2026-10-27 (close) | re-scoped run 40486871329 PASSED — `native-compile` green in 30 s on macos-14; the lane gate is live at its honest scope | ✓ green run observed | `gh run view 40486871329` |

## 14. 2026-10-27 (day's end) — RUNG-1 attempts 5–6: safety solved, the 42.8M dense line closed with data

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| Corpus v3 | v2 + 600 granted-veto rows + 500 granted-safe rows (law `decide()` unchanged; frozen cases disjoint at pair+triple); 3000 rows, 1100 allow / 1900 abstain | ✓ artifact, sha256-stamped | `perm_domain_corpus_v3.jsonl` + manifest |
| The margin rule (pre-registered) | `allow_once` iff margin > TAU; TAU selected on corpus eval ONLY (zero-unsafe, then max agreement, ties → smallest); TAU=0 byte-identical to attempt 2's argmax | ✓ mechanism | `candidate_perm_head.py --margin`; `tune_margin.py`; both PREDICTION.md |
| Attempt 5 (dense-perm-c, warm-start 5e-4) | frozen cases 12/18 = 0.667, **0 unsafe** (attempt 4: 3) at TAU=2.0 — safety solved, but no case margin cleared the threshold ⇒ degenerated to all-abstain; eval argmax 0.6655/47 unsafe | gate FAIL on agreement, verdict recorded | `dense-perm-c/` RUN-RECORD + margin_sweep + verdict |
| Attempt 6 (dense-perm-d, from scratch 1700 steps) | eval argmax 0.6021/98 (worse); frozen 12/18 = 0.667 / 0 unsafe at TAU=1.75 | line rule (< 0.75) FIRED: 42.8M dense line CLOSED | `dense-perm-d/` RUN-RECORD + margin_sweep + verdict |
| The measured frontier | ceiling of the line = attempt 4's 0.722 (argmax, 3 unsafe); 0 unsafe costs agreement down to the 0.667 baseline — representation, not calibration, binds | ✓ measured, re-scopes the rung | both RUN-RECORDs |
| Standing shipped behavior | ALL-ABSTAIN unchanged (0.667 / 0 unsafe) — best zero-unsafe point + the live data collector | ✓ | slot README |

Non-claims: fixture-half only — the live permission_gate.v1 answer
quality on the real slot is a separate later record; both runs on AC
(recorded charge current); a gate FAIL is a verdict with data, not a
shame (TRAIN-GATES law 5). Next levers are design changes: bigger trunk
(→ 50M top of the band), slot-head MLP readout over stepwise states,
veto-hardness curriculum, live-collected labeled examples. Attempt
series paused by operator instruction.

## 15. 2026-10-28 — the whole repo's CI leaves the dead directory; the owner's pin PR meets its first honest execution

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| The dead directory is empty | all four workflow files now live in `.github/workflows/` (Actions never read `archite_workflows/`; three had never triggered a run) | ✓ location law applied repo-wide | `git log a5526680` |
| apple_foundation_test repaired | unclosed YAML quote in the PR path list fixed; nonexistent `xsoulspace_agentic_harness` path dropped; ag-c + self-path triggers added | ✓ runs | run 40607784860 |
| platform_sdk_verify live + scoped | path-filtered to the 23 packages it verifies (+ script + own file); ag-c added — was an every-push trigger with no paths | ✓ runs | run 40607784919 |
| registry_publish: two latent load failures surfaced | (1) workflow-level `env` referencing `${{ runner.temp }}`; (2) after moving it to job-level env, actionlint named the law: `runner` context is unavailable at BOTH workflow- and job-level env. Fix: an early step writes `$RUNNER_TEMP`-based paths into `$GITHUB_ENV`. Verified by absence — no phantom run on the fix push | ✓ loader-clean | `actionlint` clean on all four files; run 40607783181 / 40608073810 (the two named failures) |
| The pin skew (owner finding) | both test workflows ran and failed the same way: `test_core 0.6.21` fails to COMPILE against the root's pinned `test_api 0.7.13` — CI is the first honest execution of the PR #7 pin set (Actions was dead when it merged). `flutter pub get` itself PASSED on the clone: the machine-private-override blocker from §13 is retired by the git/pub.dev pins | owner review (pin alignment) | run logs (test_core errors); pubspec.yaml `dependency_overrides` |
| Power law correction to §14 | attempt 6's RUN-RECORD says "AC at run", but its own recorded power snapshots say `pmset_source: Battery Power` (93%→58% across the run) — the snapshot is the machine's confession and it is recorded, not the prose claim | ✓ honest annotation | `dense-perm-d/record.json` power blocks |

Non-claims: green runs on the two test workflows are blocked by the
repo's own dependency pins, not by the workflows — that is what "the
workflows work" honestly means here. The lane's own gate
(`mlx_native_gate`) stayed green through the moves.

## 16. 2026-10-28 — the RUNG-1 levers: the readout lever closes with data; capacity and boundary data are pre-registered and battery-gated

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| Attempt 7a — slot-head MLP @ lr 5e-3 | DIVERGED: loss NaN from epoch 4; all 32,962 head params non-finite; NaN margins silently answer all-abstain. `train_perm_head.py` lacked train_rung0's finite guard — fixed (skip update, say so, keep going) | ✓ divergence recorded, tooling gap closed | `perm-slot-dense/attempt-7a-diverged/` (head + full log + RUN-NOTES) |
| Attempt 7b — lr 1e-3, guard on (recipe amended BEFORE any frozen case was scored; the attempt-4 precedent) | trained FINITE (max abs w 0.356, 0 non-finite) and still converged to all-abstain: flat margin sweep (every eval row ≤ 0 margin at every TAU 0→8), frozen 12/18 = 0.667 / 0 unsafe at the selected TAU=0.0 — the pre-registered FAIL condition met exactly | gate FAIL ⇒ **readout lever CLOSED for the dense trunk, with data** | `perm-slot-dense/RUN-RECORD.md` + `verdict.json` + sweep |
| The dense-trunk picture, complete | label head reaches 0.722 by over-allowing; every calibrated operating point (label-head margin, slot-head MLP margin) degenerates to all-abstain on the frozen 16M trunk | ✓ measured, re-scopes the rung | attempts 4–7 |
| Lever A — dense-perm-e (capacity) | hidden 896 → **48,655,488 params** (3.04× the closed 16M line; under the 50M band top); attempt-6 recipe verbatim on corpus v3; pre-registered line rule: closes if eval argmax < 0.70 AND frozen zero-unsafe agreement < 0.722. **NOT RUN — battery-gated** (~2.6 h needed at the measured 0.5–0.7 %/min drain; machine on battery 37%→15% across this session) | ✓ pre-registered, launch command in the rung json | `rung_dense_perm_e.json`; `dense-perm-e/PREDICTION.md` |
| Lever C — dense-perm-f (boundary data) | corpus **v4** = v3 + a 600-row balanced hard near-miss slice at every measured law boundary (3600 rows, sha256 6d43d2fa…d848e, 0 frozen-case collisions); curriculum stage 2 from dense-perm-c, lr 5e-4, 850 steps. **NOT RUN — same battery gate** | ✓ pre-registered, corpus generated + verified | `rung_dense_perm_f.json`; `dense-perm-f/PREDICTION.md`; `perm_domain_corpus_v4.jsonl` + manifest |
| **Corpus-law hole, measured** | `decide("run_command", "dart test && rm -rf /", granted)` → **allow_once**: space-separated chaining passes `command_is_safe`'s prefix match (`;` chaining happens to fail it). Excluded from all training rows; operator review, not a lane fix | ✓ recorded finding | boundary-probe log in §16 sources; `hard_rows` docstring |
| Lever D — live escalations | unchanged and honest: the gate has never run live; no policy store exists; every live all-abstain escalation is one human-labeled real example when it happens | ✓ status re-verified | slot README |
| Ledger correction | "the 42.8M dense line" was a misnomer — 42,793,280 is rung1-scale (MoE); the dense-perm trunks measure **16,006,656** (band BOTTOM, not band middle) — recorded as an annotation, history not rewritten | ✓ annotation | README + dense-perm-e PREDICTION |

Non-claims: fixture-half only; attempt 7 ran on battery (recorded; no
throughput claims); a FAIL is a verdict with data. The two staged
levers carry their own PREDICTION.md files and launch the moment the
power gate opens — no recipe decisions remain open.

## 17. 2026-10-28 — three product surfaces landed: the batch default flips ON, token streaming, and the live perm-gate slot (UNCOMMITTED)

| result | value | class | evidence |
| ------ | ----- | ----- | -------- |
| Owner decision 2 executed: fused-batch coalescing defaults ON | `LayaQwenChatServer` window defaults to **15 ms** (`defaultCoalesceWindow`); `Duration.zero` / `--coalesce-ms=0` is the explicit solo escape hatch; a dylib without the batched ABI degrades to solo either way; `coalescingActive` getter + construction gate: default coalesces, zero disables | ✓ gate (default flip; the W-G1/G2/G3 wire law unchanged) | `test/mlx_native_qwen_batch_wire_test.dart` (updated OFF reference + new flip gate); `tool/serve_text.dart` |
| Token streaming — engine | `mlx_native_qwen_stream_{api_version,start,poll,free}`: one decode thread running the SAME greedy loop (refactored `generate_greedy_cached_streaming` — one implementation, the 64/64 parity gates cover streaming by construction), cancellation reuses the request machinery; poll returns deltas cut at UTF-8 boundaries at the caller's byte watermark; the prefix pool is NOT consulted (fresh KV per stream); stream holds the global forward lock for its decode | ✓ gate | `native/mlx_native/src/{lib.rs,qwen.rs}` |
| Token streaming — Dart + wire | `NativeQwenTextEngine.generateStream` (delta stream, subscription-cancel → native cancel at the next step boundary); `LoopbackJsonServer` gained an optional stream route (`LoopbackStreamSink`); `LayaQwenChatServer` serves OpenAI-style SSE chunks for `"stream": true` (solo path only; EOS literals never ride the wire; a streaming-less dylib degrades to the completion shape) | ✓ gates **ST-G1** (joined deltas token-exact vs the completion path, ids equal) + **ST-G2** (SSE content == completion answer, finish_reason stop, `[DONE]`) — both PASS | `test/mlx_native_qwen_stream_test.dart`; `lib/src/laya_native_qwen_client.dart`; `xsoulspace_inference_local_serve` |
| The live perm-gate slot (RUNG-1) | `LayaPermGateV1` (laya product): the measured all-abstain law — **the gate never allows** (zero-unsafe by construction) — plus an append-only escalation store (sha256 question digests, raw payloads never persisted); host labels via `recordOutcome(allowed|denied)`; `labeledCount` = the acceptance metric in the making | ✓ gates **PG-G1** (never-allow incl. the measured corpus-law hole) + **PG-G2** (the tracked frozen 18 all abstain through the live slot — the LAW live, NOT an agreement claim) + **PG-G3** (append-only, digest-stable, reopen-stable) — all PASS | `xsoulspace_inference_laya/lib/src/laya_perm_gate.dart` + test |
| Git-LFS question answered | **No LFS needed**: slot harness 212 KB (already tracked), heads ~130 KB, adapters ~5.5 MB, corpora a few MB — all far under git's 100 MB limit; the 61 MB dense-trunk checkpoints fit plain git (bloat, not blockage); model snapshots stay runtime-downloaded, never in git | ✓ arithmetic from measured artifact sizes | `bench/nursery/runs/*/checkpoint`, `bench/nursery/experiments/adapter-*` |
| Native gates | cargo lib 30/30 + qwen parity 3/3 (the refactored shared decode loop stays token-exact) + artifact merge 2/2 | ✓ | `cargo test --release` |
| Dart batteries | local_serve 27/27; laya 23 pass / 1 pre-existing skip; mlx_native SERIAL battery **34 pass / 11 skip / 1 fail** — the 11 skips are the LFM2-snapshot-dependent client gates (the lfm2 snapshot is absent from the machine cache today: honest skips, not regressions; every qwen-path gate ran and passed, incl. the new stream, SSE-wire and default-flip gates), the 1 fail is the stash-proven pre-existing lazy-client red (below) | ✓ / noted | this session |
| Pre-existing red, stash-proven | `mlx_native_lazy_client_test` fails IDENTICALLY on the stashed pre-change tree: `Isolate.resolvePackageUriSync` unsupported in the load path — a toolchain drift since the 10-27 green run; disposition owed (not this session's regression) | noted (disposition owed) | `git stash` run, 2026-10-28 |
| **Paid-for deadlock (the session's defect)** | `mlx_native_qwen_stream_free` self-deadlocked: in Rust 2021 an `if let` scrutinee's `MutexGuard` lives through the whole block, so free locked `engine.requests` in the scrutinee and locked it AGAIN inside — the SAME thread, forever, with no other thread involved. Symptoms: the battery hung ~40 min at ~3 % CPU; `sample` showed a mutex wait attributed to `stream_free + 1000` and a worker thread parked in pthread bootstrap (never scheduled). Diagnosis chain: `sample` → `atos` → `nm -n` PC attribution (nearest-export names LIE at +offsets; `nm -n` bounding is the truth). Fixed by taking the Arc out before the block; stream gates PASS in 4 s after the fix | ✓ lesson + fixed | `lib.rs::mlx_native_qwen_stream_free`; the fix comment carries the law |

Non-claims: battery → AC during the run (71 %→100 % charging; the pmset
snapshot rides the test stdout) — and every gate here is an IDENTITY gate
(token-exactness, byte-equality, store append-only), power-independent by
construction; no throughput claim is made for streaming or the batch
default. Streaming keeps the serving non-claims: solo-path only, no
prefix-pool consult, no cross-request KV reuse; the fused batch keeps
completion semantics (a batch has no per-row token order to stream). The
live perm-gate slot claims the LAW (never allow) and the COLLECTOR, not
quality: real `permission_gate.v1` answer quality is written only from
accumulated labeled outcomes.

## 18. 2026-11-02 — Line IC: intent conditioning on the AR stack closes WITH DATA (no signal cell); the 2×2 scale curve measured

The owner's intent-first generation proposal ("generate intent, then fill
conditioned on it — kinda like diffusion") was split on 2026-11-02: claim A
(intent conditioning on the existing AR stack, no training) became the
pre-registered Line IC arm — gates IC-G1..G5 frozen in `MTP-GATES.md` Part 5
BEFORE any run; claim B (diffusion fill) was NOT re-opened (the Stage-0 probe
already verdicted it compute-bound 20–80× on this machine). Runner:
`tool/nursery/intent_conditioning.py` (K' rails: same corpora, split law,
chat template, strict scorer from `scoring.py`, greedy, one process per cast,
full completion caches ⇒ CPU replay). Power: AC, +1.29/+1.21 A charge current
(real supply, not the 8 W trickle), battery 56→70 % during the runs; quality
gates are not power-conditioned (ADR 0061). Wall clock: 0.6B 24 min, 1.7B
72 min.

**Rails validation:** all three 0.6B base cells reproduce the recorded
2026-10-21/26 numbers EXACTLY (perm 0.4403, veto 0.2511, clause 0.8600) —
greedy determinism across 11 days.

| cast | regime | perm strict (Δ vs in-run base, McNemar p) | veto strict (Δ, p) | clause strict (DESCRIPTIVE, 150 rows, coverage 0.254 ⇒ never a gate input) | IC-G4 |
| ---- | ------ | ------------------------------------------ | ------------------ | --------------------------------------------------------------------------- | ----- |
| 0.6B | base   | **0.4403** (outside 0) | **0.2511** (outside 0) | **0.8600** (outside 0) | — |
| 0.6B | closed | 0.4369 (−0.34 pp, p=1.0; outside 5) | 0.2599 (+0.88 pp, p=0.81) | 0.8267 (outside 4) | **FAIL** — malformed picks 71 % (perm), 100 % (veto), 99 % (clause): the base 0.6B writes prose instead of choosing from the 4-intent vocabulary |
| 0.6B | self   | 0.3823 (**−5.80 pp, p=1.5e-5**, 17-0 discordant; outside 44) | 0.2555 (+0.44 pp, p=1.0; outside 14) | 0.6733 (**−18.7 pp**, p=1.5e-8; outside 14) | pass (unique 279/293, top share 1.4 %) — non-degenerate but paraphrase-shaped, and harmful |
| 1.7B | base   | **0.5154** (outside 16) | **0.3392** (outside 10) | **0.1067** (outside 39) | — |
| 1.7B | closed | 0.2901 (**−22.53 pp, p=3.0e-9**; outside 145) | 0.3436 (+0.44 pp, p=1.0; outside 20) | 0.0267 (outside 132) | pass (malformed 6.1 %) — the 1.7B CAN select closed intents untrained |
| 1.7B | self   | 0.1604 (**−35.50 pp, p=3.3e-19**; outside 206) | 0.2335 (**−10.57 pp, p=1.2e-7**; outside 85) | 0.0400 (outside 113) | pass (unique 232/293, top share 10.9 %) |

**Frozen verdict: FAIL — no SIGNAL cell** (IC-G1 never met: no perm cell has
Δ ≥ +5 pp with p ≤ 0.05 and veto ≥ −3 pp; every regime cell also fails IC-G5's
outside-label slack). Pre-registered **reading 3 fired**: intent conditioning
closes WITH DATA on closed-set decision shapes; claim B stays closed; the
remaining intent-first route is a generation-shaped arm with a NEW oracle —
NOT scheduled. Reading 4 also fired (self at 0.6B harms, mirroring
thinking-hurts-at-0.6B).

**The format-shift diagnosis (recorded, does NOT move the verdict).** The
1.7B strict collapses are largely FORMAT, not judgment: with a Procedure line
in the prompt, 1.7B answers `label\n\njustification…` (the 145/206 outside
cells predominantly begin with a legal label). The frozen gate is strict and
stays strict — a scorer swapped after seeing data is a knob. The legacy
(content-level substring) reads were computed for the record: they are
flat-or-degenerate too — closed@1.7B perm legacy **0.5597 == the trivial
majority baseline exactly** (the arm collapsed to abstain-with-justification),
self@1.7B perm legacy 0.5461 ≈ base legacy 0.5324, veto closed legacy +5.3 pp
(the only weak positive anywhere; secondary task, C-4-hazard scorer,
non-gating). So the confound does not hide a win: at content level, intent
conditioning buys nothing on these shapes either.

**New baseline facts measured along the way:**
- 1.7B base BEATS 0.6B base on judgment-shaped cells (perm 0.5154 vs 0.4403;
  veto 0.3392 vs 0.2511) but COLLAPSES on clause (0.1067 vs 0.8600): the
  larger model refuses the bare-label format on short memo text — strict
  accuracy at 1.7B is format-bound, not judgment-bound, on that task. Any
  future 1.7B closed-set arm needs a format-compliance control.
- Closed-intent SELECTION is scale-gated without training: 6.1 % malformed at
  1.7B vs 71 % at 0.6B — the same format-compliance gap the trained LoRA
  ranker exists to close at 0.6B (ranked == generated, zero illegal labels).

Non-claims: no training happened; nothing here transfers credit to or from
the confirmed LoRA ranker (different adapter, different label space). No
generation-shaped (swe/decomp) intent claim exists in either direction — the
arm measured closed-set decision shapes only. The veto/closed legacy +5.3 pp
is NOT a finding (secondary task, non-frozen scorer, no paired significance
computed for a non-gate). Tok/s and wall-clock numbers are informational
(AC-asserted, charge current recorded). Evidence:
`bench/nursery/experiments/intent-conditioning-{0.6b-2026-11-02T21-05-29Z,
1.7b-2026-11-02T21-29-46Z}/` (run records + per-item completion caches +
`intent-conditioning-verdict-*.json`).

### §18 addendum — 2026-11-03 CPU replay: the experiment critiqued against its own caches (DESCRIPTIVE, post-hoc; the frozen verdict stands)

Owner asked for a criticism of the IC arm. Three criticisms are measurable
from the cached completions with zero GPU (`tool/nursery/ic_replay.py`, new
tracked replay tool; full output `bench/nursery/experiments/ic-replay-2026-11-03.txt`).
These extractors were NOT frozen before the run, so every number here is a
hypothesis generator, never a gate input, in either direction.

**D1 — format-normalized reads (first-line-exact / starts-with-label, both
C-4-safe word-boundary matchers; identical results under both).**

| cell | strict Δ | first-line Δ | paired p (first-line) | discordance |
| ---- | -------- | ------------ | --------------------- | ----------- |
| 0.6B self perm | −5.80 pp | **−5.80 pp** | 1.5e-5 | 17-0 — the harm SURVIVES format normalization: real judgment damage |
| 0.6B self clause | −18.7 pp | −14.7 pp | 2.7e-5 | 25-3 — survives |
| 0.6B self veto | +0.44 pp | +3.96 pp | 0.19 | 14-23 — mildly positive, ns |
| 1.7B closed perm | −22.5 pp | **+2.73 pp** | 0.53 | **124/293 items flip** with net ~0 — conditioning noise atop a below-trivial decider |
| 1.7B self perm | −35.5 pp | +1.02 pp | 0.86 | 129/293 flip, net ~0 |
| 1.7B closed veto | +0.44 pp | **+5.73 pp** | **2.4e-4** | **13-0, all flips one-way repairs** — the only clean positive anywhere |
| 1.7B self veto | −10.6 pp | −2.64 pp | 0.35 | 17-11 |
| 1.7B clause (all) | ≤0.11 | ≤0.15 | — | clause at 1.7B is broken BEYOND format repair (base first-line 0.14) |

Reading: the 1.7B strict collapse is largely a format artifact (judgment-level
deltas shrink to flat), but "flat" sits on top of a base decider that is
itself at/below trivial on perm (0.5154/0.5324 vs 0.5597 majority) — the arm
conditioned a process that was not working, and the 124-item churn with net
zero is what noise looks like. The veto cell (where 1.7B base IS above
trivial, 0.3392 vs 0.2819) is exactly where the one clean positive appeared.
The +5.73 pp/13-0/p=2.4e-4 read survives Bonferroni over the ~36 replay
reads — and remains descriptive: post-hoc scorer, secondary task, never
pre-registered. It is recorded as the IC-2 hypothesis (VERDICTS.md O row).

**D2 — intent content (self arm):** zero answer leaks on perm/veto at both
casts (intents never mention label words) — the manipulation was clean; the
intents were procedurally-phrased paraphrases. clause@1.7B: 13/150 misleads
(intent mentions a non-gold label), 1 leak. IC-G4 measured diversity, never
type or usefulness — a design gap, partially closed here.

**D3 — constant-prefix check (closed arm):** pick top-share **0.92 (0.6B
perm), 1.00 (0.6B veto), 0.99 (1.7B perm), 1.00 (1.7B veto)** — nearly
always `match_against_policy`. The closed arm never varied the intent per
item: it was an accidental FIXED-PROCEDURE control. Consequences: (a) the
arm cannot answer "does the RIGHT intent help" — only "does a procedural
prefix help"; (b) the four-intent vocabulary carried ≈0 bits/item (one
option nearly always chosen, and the options were near-synonyms); (c) the
missing `fixed`/`random`-procedure controls were never needed as separate
arms — `closed` WAS the fixed arm, unplanned.

**What changes / what does not.** The frozen verdict (FAIL, reading 3) is
untouched — it was computed by the frozen scorer on the frozen design and a
scorer or design swapped after seeing data is a knob. What the replay
changes is the SCOPE of the negative: the 0.6B closures are solid (self
harms at judgment level; closed is degenerate untrained); the 1.7B closure
is format-conditional, and at judgment level the honest summary is "flat on
a below-trivial decider, one clean unreplicated positive on the task where
the base actually works." Recorded as such in VERDICTS.md (F row amended +
new O row: the IC-2 judgment-level design). Design lessons banked: match
the instrument to the manipulation (format-normalized co-primary or a
bare-label instruction in ALL arms), vary the thing whose value you test
(information-bearing intents + fixed/random controls), condition a WORKING
decider (the confirmed adapter, not the base), and match the task shape to
the hypothesis (skeleton→fill belongs on generation-shaped tasks, which owe
a new paired blind-rubric oracle).

## 19. 2026-11-03 — Line IC-2: the crumb replicates under pre-registration (PASS, one SIGNAL cell); preambles are lethal to adapter-served slots

Owner go on the full IC-2 design after the §18-addendum critique. Part 6
frozen BEFORE any run; the three design repairs: first-line extraction as
the frozen PRIMARY (canonical `extract_label_first_line` in `scoring.py`),
the missing `fixed`/`random` procedure controls, and the CONFIRMED untagged
adapter as the 0.6B decider under the IC2-G0 reproduction gate. Power: AC
both legs (snapshot in the run records); wall clock 22 min (0.6B+adapter) +
34 min (1.7B).

**IC2-G0 PASSED EXACTLY:** adapter base perm 0.8737 / veto 0.7533 — the
2026-10-21 record to 4 dp, coverage 1.0. The 1.7B base also reproduced IC-1
exactly (perm first-line 0.5324/strict 0.5154; veto 0.3612/0.3392).

| decider | task | arm | first-line acc | Δ vs base | McNemar p | discordant (base,arm) | strict acc (co-report) |
| ------- | ---- | --- | -------------- | --------- | --------- | --------------------- | ---------------------- |
| 0.6b+adapter | perm | base | **0.8737** | — | — | — | 0.8737 |
| 0.6b+adapter | perm | fixed | 0.5700 | **−30.38 pp** | 7.2e-24 | (92, 3) | 0.5700 |
| 0.6b+adapter | perm | random | 0.5802 | **−29.35 pp** | 5.2e-23 | (89, 3) | 0.5802 |
| 0.6b+adapter | perm | evid | 0.5836 | **−29.01 pp** | 1.0e-22 | (88, 3) | 0.5836 |
| 0.6b+adapter | veto | base | **0.7533** | — | — | — | 0.7533 |
| 0.6b+adapter | veto | fixed | 0.7709 | +1.76 pp | 0.64 | (19, 23) | 0.7709 |
| 0.6b+adapter | veto | random | 0.7445 | −0.88 pp | 0.86 | (16, 14) | 0.7445 |
| 0.6b+adapter | veto | evid | 0.6652 | **−8.81 pp** | 1.2e-2 | (39, 19) | 0.6652 — **IC2-G3 FAIL** (14.5 % malformed picks) |
| 1.7b | perm | base | 0.5324 | — | — | — | 0.5154 |
| 1.7b | perm | fixed | 0.5597 | +2.73 pp | 0.53 | (58, 66) | 0.2935 |
| 1.7b | perm | random | 0.5290 | −0.34 pp | 1.00 | (55, 54) | 0.3174 |
| 1.7b | perm | evid | 0.5461 | +1.36 pp | 0.78 | (55, 59) | 0.4369 |
| 1.7b | veto | base | 0.3612 | — | — | — | 0.3392 |
| 1.7b | veto | fixed | **0.4185** | **+5.73 pp** | **2.4e-4** | **(0, 13)** | 0.3436 |
| 1.7b | veto | random | 0.3789 | +1.76 pp | 0.39 | (4, 8) | 0.3436 |
| 1.7b | veto | evid | 0.2819 | **−7.93 pp** | 7.6e-6 | (18, 0) | 0.2819 |

**Frozen verdict: PASS** — one SIGNAL cell (`1.7b/veto/fixed`), IC2-G3/G6
clean on it. **IC2-G2 crumb law: REPLICATED** — the exact IC-1 numbers came
back (+5.73 pp, p=2.4e-4, 13-0) under pre-registration, and `random` did not
replicate ⇒ the frozen reading: **the CONTENT of the specific procedure
string matters**, not any-prefix priming. **IC2-G5 harm fired in four
cells** (adapter perm ×3, adapter veto evid). Inert band (G4): no cell —
every arm either harms, churns flat with wide CIs (1.7B perm), or signals.

**Mechanism readings (labeled interpretation, not gates):**
- The evid arm's SELECTION distributions explain its failure: perm picks are
  near-constant on BOTH deciders (`command_and_context_clean` 289/293
  adapter, 292/293 base-1.7B — everything "looks clean"), and 1.7B veto
  picks are constant 227/227 (`operation_destroys_or_truncates_data`) with
  the answer collapsing to exactly the trivial majority 0.2819. The adapter
  DID vary its veto picks per item (94/90/33/10) and still lost 8.8 pp —
  selecting evidence does not help if the second pass cannot use it.
  Model-selected intent at judgment level is measured-dead in this shape.
- The fixed arm's win is a FORMAT ANCHOR with content-specificity: the
  Procedure line converts prose-first answers into label-first answers
  (outside 5→0 on 1.7B veto), which nets a gain only where the underlying
  judgment is real (veto base 0.3612 > trivial 0.2819), nets ~0 amid huge
  churn where judgment is at chance (perm: §18 D1's 124/293 flips), and is
  catastrophic on a format-trained decider (the adapter's OOD collapse).
- Reading-tension note (recorded, resolved by the specific law): Part 6's
  general reading 2 ("fixed/random SIGNAL without evid ⇒ format priming")
  fired literally, but IC2-G2's MORE SPECIFIC frozen law (fixed ∧ ¬random ⇒
  content matters) also fired and governs the crumb's interpretation.

**Product law (the durable outcome):** never prepend preamble lines to
adapter-served decision slots (−30 pp, p≈1e-23, three independent arms).
The narrow positive — one constant string, one task shape, one cast, on a
decider still at 0.42 — is a mechanism fact to bank, NOT a product feature.

Non-claims: the SIGNAL cell does not make intent conditioning a product
mechanism; the perm cells at 1.7B stay descriptive (below-trivial decider);
strict-vs-first-line divergence persists as a measured artifact class
(1.7b/perm/fixed: strict 0.2935 vs first-line 0.5597 — the same completions,
two instruments, and the frozen primary is the first-line by pre-run law).
Evidence: `bench/nursery/experiments/ic2-judgment-{0.6b_adapter-2026-11-03T09-12-49Z,
1.7b-2026-11-03T09-25-46Z}/` (run records + full per-item caches) +
`ic2-judgment-verdict-2026-11-03T09-59-08Z.json`; runner
`tool/nursery/ic2_judgment.py` (tracked).

## 20. 2026-11-03 — Line SK: skeleton→fill on constrained generation closes WITH DATA (FAIL, no SIGNAL cell) — but the control discrimination is the lane's cleanest yet

Part 7 frozen BEFORE the run (deterministic decompression oracle — the
blind-rubric judge stays OWED for the open-form tail only, not built, not
scheduled). Generated corpus: 90 sha-pinned cases (`cac823a7…`, generator
rule v2 after its pre-freeze audit — plain-word entity ranking promoted
`nearly`/`always` and was rejected for identifier-first ranking). Deciders:
1.7B primary, 0.6B scale point, NO adapter (category error after §19's harm
law). Power: AC, 100 %, both legs (24 min + 15 min). SK-G0 PASSED (sha,
n, oracle constants all matched the freeze).

| corpus | decider | arm | pass | Δ vs base | McNemar p | discordant (base,arm) |
| ------ | ------- | --- | ---- | --------- | --------- | --------------------- |
| generated 90 | 1.7b | base | 0.3444 | — | — | — |
| generated 90 | 1.7b | skeleton | 0.4333 | **+8.89 pp** | 0.215 | (12, 20) |
| generated 90 | 1.7b | generic | 0.3444 | **−0.00 pp** | 1.000 | (13, 13) |
| generated 90 | 0.6b | base | 0.2222 | — | — | — |
| generated 90 | 0.6b | skeleton | 0.3111 | **+8.89 pp** | 0.185 | (10, 18) |
| generated 90 | 0.6b | generic | 0.1222 | −10.00 pp | 0.064 | (14, 5) |
| tracked 10 | 1.7b | base / skeleton / generic | 10/10 · 10/10 · 7/10 | — | — | SK-G2 continuity ✓ at 1.7B |
| tracked 10 | 0.6b | base / skeleton / generic | 10/10 · 7/10 · 4/10 | — | — | **SK-G2 VIOLATION at 0.6B** (7 < 10−1; recorded two-pass artifact) |

**Frozen verdict: FAIL** — no SIGNAL cell; SK-G5's "neither" branch fired:
the intent-first line closes WITH DATA on constrained generation as well;
only the open-form route (owed rubric oracle) remains. TWO independent gate
facts block any stronger claim, both frozen before the run:

1. **Underpowered trend, not a signal.** skeleton−base = **+8.89 pp on BOTH
   deciders, identically** (the same 8 of 90 net flips), above the +5 pp
   margin — but p = 0.215/0.185 at n = 90 (CI ≈ [−3, +21]). The margin was
   frozen without a power calculation against this n; the trend is real
   arithmetic and stays DESCRIPTIVE.
2. **SK-G3 FAIL on both deciders** (skeleton entity coverage 0.304 at 1.7B,
   0.353 at 0.6B, vs the frozen ≥ 0.40): the pass-1 skeletons do NOT carry
   the gold entities verbatim — the model paraphrases ("the text lane's
   bench tool") where the frozen entity rule demands identifier strings
   (`napbench_text_lane.dart`). By the frozen law a G3 violator's skeleton
   cells cannot be SIGNAL even if p had cleared. The G3 rule and the entity
   rule are lexically mismatched — a design defect of the gate, named here,
   fixed only in a NEW arm.

**The control discrimination (the durable mechanism fact).** `generic`
(constant pseudo-skeleton, identical two-pass structure) moved 1.7B by
EXACTLY 0.00 pp (13-13 mirror discordants) and HARMED 0.6B (−10 pp,
p=0.064): the two-pass STRUCTURE buys nothing by itself — whatever the
+8.89 pp trend is, it rides the skeleton's CONTENT. This is the same
content-vs-structure discrimination IC-2's fixed/random split produced on
veto (§19), now replicated in generation shape. Failure-reason breakdown:
entity recall dominates both arms' failures (base 55, skeleton 42 of ~59-51
fails); the cap/one-line laws bind rarely — the corpus measures fact
retention, as designed.

Non-claims: no product claim — the trend is underpowered and G3-blocked;
the tracked-10 numbers are a continuity check, not a scorecard (both
deciders at ceiling there, headroom law moot); corpus is one provenance
family (project-memory prose); pass-1 and pass-2 are the same decider (no
separate planner). Reopening requires a NEW arm: either n large enough to
resolve +8.9 pp at p ≤ 0.05 (≈ 350+ cases by the observed discordance), or
a skeleton-carry criterion that is not lexically mismatched with the entity
rule (or both), each with its own frozen Part.

Evidence: `bench/nursery/experiments/sk-fill-{1.7b-2026-11-03T10-01-55Z,
0.6b-2026-11-03T10-25-47Z}/` (records + full per-case caches incl. every
skeleton text) + `sk-fill-verdict-*.json`; runner `tool/nursery/skeleton_fill.py`;
generator `tool/nursery/decomp_skeleton_dataset.py` (tracked; the dataset
itself is gitignored working material, sha-pinned in the run records).

## 21. 2026-11-03 — the intent-first line is RETIRED by owner decision

Owner instruction (2026-11-03, after the arc report): stop the intent-first
experiment line, update docs, clean up. Scope of the retirement:

- **No new arm will be registered from the intent-first hypothesis family.**
  Lines IC (§18), IC-2 (§19) and SK (§20) are the line's complete record;
  their frozen Parts (MTP-GATES 5–7) stand as written, post-run blocks
  included.
- **The two owed items are DECLINED, not parked:** the ≈350-case SK rerun
  (non-lexical skeleton-carry criterion) and the blind-rubric oracle for
  open-form quality. Neither is owed as open debt any more; if either is
  ever wanted, it returns as a NEW line with its own frozen Part and its
  own owner go — the standard F-law route, now explicitly unowned.
- **What survives the retirement is product knowledge, not an experiment
  queue:** the no-preamble product law for adapter-served slots (§19,
  IC2-G5), the content-vs-structure mechanism fact (replicated across
  judgment and generation shapes, §19–§20), the crumb itself as a narrow
  banked mechanism (1.7b/veto fixed prefix, +5.73 pp, p=2.4e-4, 13-0), and
  the scale-gating facts (closed-intent selection 6.1 % vs 71 % malformed;
  1.7B clause format-bound). These are cited by the product rows
  (VERDICTS ✓/F tables), not by any open queue.
- **The lane's next questions are elsewhere and unchanged:** the
  completion@N loop-bench (reasoning-track direction #1, never measured),
  consolidation of the confirmed ranker/gate/streaming surface, and the
  decision-compile policy (direction #3). The staged RUNG-1 levers and the
  corpus-law hole review keep their own pre-registrations.

Cleanup performed with the retirement: the three SMOKE plumbing dirs under
`bench/nursery/experiments/` deleted (4-row caches, zero evidential value;
the gated runs' caches stay); session temp artifacts removed; no tracked
file deleted. Evidence for the retired line remains where it always lived:
the run dirs + verdict jsons under `bench/nursery/experiments/` (gitignored
by lane convention) and the tracked records cited above.
