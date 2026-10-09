# 0055 — Qwen on the composition API, kernel-capture attribution, and the hard-law research verdicts

Date: 2026-10-09
Status: Accepted (P0–P2 implementation gated by the evidence ladder below;
observed numbers are appended per rung, ADR 0032 protocol)

## Context

ADR 0054's ladder is executed: every rung R0–R5 either passed its gate or is
honestly recorded as a failure with an owner. The closure audit (2026-10-09)
leaves four named debts, none of them "model parity" — that is reached and
gated:

1. **The composition API has parity only on the laya path.** `qwen.rs` already
   dispatches every op through `bindings::eval` (the binding table's second
   consumer — that is how `RmsNormFusedMsl` and `DequantGemmMsl` landed
   without touching it), but its forward is an imperative walk: no declared
   plan tree, no `LAYA_*_DUMP` review surface, no plan-derived µbench, no
   node-grouped profile. Two models, two architectures inside one cdylib.
2. **The 3–4× long-context decode gap vs python (R3a) has no kernel-level
   attribution.** Op-level probing is exhausted: individual ops probe
   identical-or-slower on python, the gap only appears at T≈2048, and the
   vendored build was believed to lack kernel capture.
3. **Two custom-kernel retries are recorded with paper headroom**
   (simdgroup-tiled skinny-GEMM; multi-n dequant-GEMV). Retrying them blind
   would repeat the R4 pattern: fast kernel, wrong target.
4. **The hard laws (no continuous batching, no GGUF, no autodiff/training)
   and the 1.2B q4 tok/s non-claim were never re-examined against evidence.**

## Decision

**(P0) The qwen decode step becomes a declared plan.** `Qwen3::forward_step`
gains a plan path (`LAYA_QWEN_PLAN=1`, opt-in until gated, then default):
one `Plan` per decode step, rebuilt per step (the RoPE offset is a
per-step constant — a shape-keyed compiled closure needs an offset-as-input
op variant first; designed below, NOT this rung). The KV cache enters the
plan as inputs (the 2L allocated buffers) and leaves as declared outputs
(functional `slice_update`), so execution stays python-parity down to the
slice/update order. `plan.rs` gains a multi-output executor
(`execute_outputs`); the laya `execute` becomes its two-output case.
Prefill stays imperative (KV-only chunks, varying shapes, low value).
Gates: plan-path logits bit-identical to the imperative path on a live
prompt, then the full 64/64 greedy fixture with the plan path routing the
decode loop. `LAYA_QWEN_PLAN_DUMP` writes the plan JSON — the reviewable
story of the decode step.

**(P1) Attribution before optimization: wire GPU capture, capture both
legs, diff per kernel.** The vendored mlx-c already exposes
`mlx_metal_start_capture/stop_capture` (MTLCaptureManager GPU-trace
documents) — the earlier "MX_METAL_DEBUG not wired" note was wrong about
the mechanism that matters; NO vendored-source edits. New externs + safe
wrappers; a `--ignored` capture harness runs the 2k-context decode under
capture on the Rust engine and (via `mx.metal.start_capture` in the
reference venv) on python; the traces are parsed for per-kernel GPU
durations and the diff lands in the evidence ladder. The 3–4× gap gets an
owner and a mechanism, or stops being claimed.

**(P2) Kernel retries ride P1's evidence.** The simdgroup-tiled
skinny-GEMM and multi-n dequant-GEMV attempts run after the capture diff
says where decode time actually goes. Gates are unchanged and non-negotiable:
golden/fixture parity, then ≥1.3× µbench, else the table keeps mlx-c and the
attempt is recorded. Two failed attempts with the same evidence class close
the lane permanently (ladder law).

**(Hard laws re-affirmed with research, not habit:**

- **Continuous batching (Orca/vLLM iteration-level scheduling) stays
  excluded.** What it buys: 2–4× throughput at high concurrency by
  recomposing the batch every decode step; what it costs: a request
  scheduler, paged/shared KV, preemption — and *worse p99 tail latency*.
  Our workloads are solo decisions (B=1 latency-bound, the opposite
  regime) and single-session decode. The middle step if multi-session
  demand appears is a STATIC batch (B>1 prompts in one forward — qwen.rs
  is currently B=1-shaped), which is a shape change, not a scheduler.
- **GGUF stays excluded.** GGUF is llama.cpp's ecosystem format; on Apple
  Silicon mlx-native quantized kernels measurably beat llama.cpp/GGUF
  (~15–40% generation throughput, less on-the-fly dequant). Adopting GGUF
  here would add a parser + foreign quant schemes (Q4_K etc.) to reach a
  strictly slower kernel path on our only supported host. Revisit only if
  cross-platform (non-Apple) hosts enter the mesh — which is the Android
  non-MLX ADR's territory, not this engine's.
- **Autodiff/training stays excluded.** MLX's `value_and_grad` + LoRA is
  real and works on M-series, but activation memory scales with sequence
  length (practical LoRA limits ~3.5k tokens on 16 GB), it drags in
  optimizer state, checkpointing, and a training harness — a different
  product. If fine-tuning demand appears it gets its own ADR and most
  likely runs python mlx-lm beside this engine, not inside it.
**

**(The 1.2B q4 tok/s gate gets a concrete path, not a hand-wave.** The
"≥45 tok/s 1.2B q4 class" row from ADR 0051 is unimplementable today
because LFM2.5-1.2B is a Liquid LFM2 hybrid: 16 blocks = 10 double-gated
short-convolution blocks (O(n), NO KV cache — a sliding conv state instead)
+ 6 GQA blocks; mlx-community conversions exist. Implementation = a new
arch module beside `qwen.rs` (short-conv decoder + conv-state cache; the
GQA blocks reuse the existing attention/quantized-linear machinery) + a
python-parity fixture via the existing harness pattern. Estimated as the
next rung-sized increment after P0–P2, product-demand-gated.

## Consequences

- One plan surface governs both models (dump/review/µbench/profile); the
  RMSNorm kernel stops being special-cased wiring.
- The decode gap either gets a mechanism (kernel capture diff) or is
  retracted as a claim.
- Kernel retry lanes close permanently on their second same-evidence failure.
- The laws are now evidence-backed; changing one requires an ADR amendment,
  not a code change.
- Non-goal recorded: continuous batching, GGUF, training paths, and the
  qwen compile route (blocked on an offset-as-input Rope variant — designed,
  not scheduled).

## Evidence ladder (appended per rung)

- **P0 (2026-10-09) — the qwen decode step is a declared plan. LANDED, gates
  GREEN:** `plan.rs` gained the multi-output executor (`execute_outputs`;
  laya's `execute` is its two-output case; `Plan.outputs` with serde default
  keeps serialized laya plans valid). `qwen.rs::build_step_plan` declares the
  step node-for-node — embed gather, per-layer attention/MLP, functional
  KV `slice_update` writes (2L declared outputs), final norm, lm_head — with
  the RoPE offset and slice bounds as per-step plan constants (plan rebuilt
  each step; the shape-keyed compile route needs an offset-as-input Rope
  variant first, recorded non-goal). Routes via `step_logits(use_plan)` —
  env `LAYA_QWEN_PLAN=1` in `generate_greedy`, in-process selection in the
  gate. `LAYA_QWEN_PLAN_DUMP=<file>` writes the plan JSON; 
  `LAYA_QWEN_PLAN_DEBUG=1` prints the pool manifest. **Gates: plan-path
  logits BIT-IDENTICAL to the imperative walk over 8 live decode steps
  (tests/qwen_plan_parity.rs, f32-bits compared), and the full fixture
  under plan routing 64/64 greedy tokens** (`LAYA_QWEN_PLAN=1 cargo test
  --test qwen3_parity`). Paid-for lesson: pool indices are positional —
  a `pin` that registers an array already carried manually (tokens, cache
  buffers) shifts every subsequent Input index by one and surfaces as a
  bogus reshape; one registry, assembled once.
- **P1 (2026-10-09) — GPU-capture tooling landed; the 3–4× long-context
  decode gap is RETIRED as a machine-state measurement artifact.** Tooling:
  `mlx_metal_start_capture`/`stop_capture` were ALREADY in the vendored
  mlx-c C API (the earlier "MX_METAL_DEBUG not wired" note was looking at
  the wrong mechanism — no vendored-source edits needed); safe wrappers in
  `mlx.rs`, `src/bin/qwen_capture_trace.rs` writes a real
  MTLCaptureManager trace (opens in Xcode Instruments; requires launching
  with `METAL_CAPTURE_ENABLED=1` — without it the capture layer is not
  injected and start fails; traces are Apple's proprietary MTSP packages,
  not parseable in-process), `src/bin/qwen_decode_bench.rs` +
  `tool/py_decode_scaling.py` implement the interleaved same-power-state
  A/B protocol (the ADR 0051 power-state law, applied to ourselves).
  **Attribution: interleaved p50 at 2k = Rust 15.3–23.7 ms vs python
  16.3–18.4 ms (0.9–1.3×, parity); at 4k Rust 16.6–17.6 ms vs python
  21.9–23.4 ms (0.71–0.75×, Rust FASTER).** The previously recorded 3–4×
  (and an 82.7 ms first sweep this session) came from cross-machine-state
  comparisons — the R3a exact-size-KV fix plus state-clean measurement
  leave no gap to attribute. **Retired, not owned.** Residual real signal:
  Rust p90 spikes (33–72 ms vs python 17–23 ms at 2k, bimodal) — owner
  recorded for a future session with hypotheses (command-buffer commit
  cadence, allocator pressure, DVFS transitions) and the capture tool to
  chase them.
- **P2 (2026-10-09) — both kernel retries DECLINED on P1's evidence; lanes
  close.** The ladder's own gate was "retries ride P1's evidence" — the
  evidence retired the target. (1) dequant-GEMV (best 0.83–0.98×): the
  only shape with paper headroom is lm_head, where mlx sits ~1.4× above
  the packed-stream floor — but the absolute stakes are ~6 µs/step
  (0.83 MB of q4 weights ≈ 14 µs at floor vs ~20 µs measured) inside a
  ~16 ms step: proportionally real, absolutely negligible. Per-layer
  shapes stay dispatch-latency-bound, which no kernel fixes. (2)
  simdgroup-tiled skinny-GEMM (0.12–0.21×): closing to ≥1.3× means beating
  mlx's simdgroup GEMM at shapes where mlx runs 5–6× above the
  weight-stream floor (i.e. compute/tile-bound, where its tiles are
  good) — expected value negative against a hand-tuned vendor kernel, in
  a lane whose decode-gap motivation no longer exists. Both lanes close
  permanently per the two-same-evidence-failures law; the tables keep
  mlx-c. Any reopening needs NEW evidence class (a workload where these
  matmuls dominate a measured profile), not another attempt.
- **1a/1b (2026-10-09, commit cdae93d9) — the declared plan promoted to
  DEFAULT for decode AND prefill; composition-API unification complete.**
  `LAYA_QWEN_PLAN=0` opts back out (the RMSNorm-row pattern). The plan
  builder generalizes to prefill chunks: variable L, causal sdp, KV-only
  tail (`with_head=false` keeps R5's dead-lm_head waste dead); cache
  growth hoisted OUT of the plan into `KvCache::ensure_capacity` —
  byte-for-byte `update_one`'s policy (the first draft's
  `old_alloc + block − prev` math diverged and the bit-parity gate caught
  it before any ship). Gates: decode plan logits BIT-IDENTICAL (8 live
  steps, f32 bits), prefill plan caches bit-identical (2 chunks / 300
  tokens crossing the growth boundary), 64/64 fixture under the DEFAULT
  route and under `LAYA_QWEN_PLAN=0`, test_fresh 63/63 @ 0.0/1.5e-8,
  q8 63/63 @ 0.0164.
- **2 (2026-10-09, commit 14ed3f8f) — the decode p90 spikes attributed and
  fixed.** Per-step sample dumps over 600-step runs pinned the spikes to
  KV-cache GROWTH steps exactly (offsets 2049/2305/2561: 34–44 ms vs a
  ~14.7 ms baseline; the update_one realloc — new buffer + trim/concat
  across 56 buffers). In-process A/B via `KvCache::reserve`: spikes gone,
  baseline unchanged. `generate_greedy` now reserves the whole
  prompt+max_tokens window up front, moving the one growth into the
  prefill phase. Residual end-of-run drift (~+1 ms over 600 steps) =
  thermal, recorded not owned.
- **LFM2 rung (2026-10-09) — the "≥45 tok/s 1.2B q4 class" gate is MET.**
  `src/lfm2.rs`: the Liquid LFM2/LFM2.5 hybrid decoder op-for-op vs the
  pinned venv's `mlx_lm/models/lfm2.py` — 10 double-gated short-conv
  blocks (in_proj → split B/C/x → B·x → sliding conv state [last
  L_cache−1 rows] → depthwise `conv1d` [new `Op::Conv1d` binding,
  groups=channels] → C·conv → out_proj; O(n), NO KV cache) + 6 GQA
  attention blocks (the qwen3 machinery reused: q/k layernorms, RoPE at
  the shared offset, 256-step KV growth, causal chunked prefill), swiglu
  MLPs, RMSNorms, quantized tied embedding as head. Fixture:
  `testdata/lfm25_12b_parity.json` (venv-recorded prompt_ids +
  greedy_ids; the Qwen-specific bpe.rs deliberately not used).
  **Gate: 64/64 greedy tokens match the reference; decode 49–53 tok/s on
  AC (reference leg 46.9) — the ADR 0051 row holds on the Rust host.**
  THE PAID-FOR LESSON (found by per-layer dump bisect, layer 2 attention,
  decode step 1: the keys cache read all zeros): `attn_update` is
  FUNCTIONAL — the written buffers must be stored back into the slots
  (`*k = Some(kc...)`) or every decode step attends to an empty cache;
  the prefill HIDES the bug because its single chunk consumes the
  update's return value directly. Dart FFI for LFM2 = the follow-up
  increment (the qwen FFI pattern exists); not this rung.

<!-- EVIDENCE:APPEND -->
