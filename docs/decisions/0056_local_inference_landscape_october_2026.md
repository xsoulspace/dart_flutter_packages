# ADR 0056: Local inference landscape — October 2026 verdicts and ecsai_harness application

Date: 2026-10-09
Status: Accepted (verdicts; each adoption still ADR-first at rung time)
Supersedes: none
Amends: none (hard laws restated, unchanged)

## Context

The Metal ladder (ADR 0051 → 0055) serves laya decisions, Qwen3, and
LFM2.5 through one Rust/MLX dylib behind Dart FFI. With the FFI rung and
consolidated bench landed (ADR 0055, commit 63b25bba), this record
answers, with sources: how fast and applicable is the stack now, what
the real bottlenecks are, what the October 2026 research landscape
offers, and what the harness (`~/xs/ecsai_harness`) should adopt.

Evidence classes are separated per the claims law: **[measured]** = our
runs with power state recorded; **[reported]** = vendor/community
numbers we have not reproduced; **[verdict]** = our decision.

## Current state [measured]

`model_bench` (release, Apple M1, AC), decode = greedy single-stream:

| model | load s | prefill-512 tok/s | decode tok/s (p50) | decode@2k (p50) |
|---|---|---|---|---|
| Qwen3-0.6B q4 | 0.16 | 1363 | 84.9 (10.7ms) | 67.7 (14.4ms) |
| Qwen3-0.6B bf16 | 1.01 | 1590 | 38.7 (25.5ms) | 33.7 (28.8ms) |
| Qwen3-1.7B q4 | 0.66 | 468 | 44.9 (22.1ms) | 39.2 (25.3ms) |
| LFM2.5-1.2B q4 | 0.50 | 651 | 70.1 (13.8ms) | 64.3 (15.0ms) |

Laya decision route: B=1 p50 96.5 ms/decision on AC (ADR 0051 AC
evidence; parity 63/63 re-proven 2026-10-09). The python mlx_lm serve
path it replaces measured p50 244–1105 ms/turn in napbench — the
in-process engine removes serve/IPC overhead entirely.

Position vs the field [reported]: Liquid ships LFM2.5-2.6B at ~220
tok/s on M5 Max / ~30 tok/s on a phone ([AlphaSignal](https://alphasignal.ai/news/liquid-ai-s-lfm2-5-2-6b-beats-9b-models-running-entirely-on-your-phone));
our 70 tok/s for the 1.2B on a 2020 M1 (68 GB/s bandwidth) is at the
same class of speed-per-bandwidth — the engine is not the gap; the
silicon is. M5 Max/Utra move bandwidth to 600 GB/s–1.2 TB/s
([Apple newsroom](https://www.apple.com/newsroom/2026/08/apple-introduces-new-mac-studio-with-m5-max-and-m5-ultra)),
which scales decode linearly (decode is bandwidth-bound [measured:
q4≈2×bf16; 1.7B≈0.53× of 0.6B]).

Applicability [verdict]: the stack is production-applicable for its
declared regime — single-stream, on-device, Apple Silicon, decision +
bounded-generative lanes. It is NOT a serving stack (B=1 by design).

## Bottlenecks (owned, in order)

1. **Decode = weight-read bandwidth.** Every token reads every weight;
   the fix classes are smaller/quantized weights (done: q4 default) or
   not reading all weights per token (speculative verification amortizes
   the read across k candidate tokens; hybrids/MoE read less).
2. **Prefill = compute-bound.** 1363 tok/s (0.6B) means a 2k prompt
   costs ~1.5 s before the first token. Long-context products pay
   here first.
3. **Dense long-context decode falloff.** Qwen3 85→68 tok/s at 2k (KV
   reads grow per token); LFM2.5 70→64 — the hybrid's O(1) conv blocks
   and 6-of-16 KV layers are why. Architecture, not kernel quality.
4. **Product gaps, cheap:** no EOS stop in `generate_greedy`; no chat
   template for the instruct checkpoints (raw completion today);
   single-flight FFI (serialized generate).
5. **Every new architecture is a Rust port.** Qwen3.5 / Gemma 4 /
   SmolLM3 / MoE variants each need a loader + ops + parity fixture.
   The LFM2 rung is the template (venv reference → fixture → bit gate).

## October 2026 landscape — verdicts

- **ADOPT (consider at next rung): speculative decoding via a draft
  MODEL.** mlx-lm ships production speculative decoding
  ([community report: 1.6–2.3× on 70B](https://contracollective.com/blog/speculative-decoding-mlx-apple-silicon-2026);
  [LM Studio: 1.5–3× with Llama-3.2-1B drafts](https://lmstudio.ai/blog/lmstudio-v0.3.10);
  [MLX-Swift implementation](https://github.com/mlx-community/speculative-decoding)).
  Our own napbench showed LFM2.5 **self-drafting** (16 blocks) fails
  faithfulness — the untested lane is a SMALL DIFFERENT model drafting:
  Qwen3-0.6B → Qwen3-1.7B (same tokenizer, same engine). Payoff is
  real only when the target is ≥1.7B [verdict]; our B=1 chat targets
  run 45–85 tok/s already. Verify-then-accept also fits the decision
  lane's deterministic gates. ADR-first if/when a ≥1.7B local model
  becomes the default.
- **ADOPT (cheap, product): LFM2.5-family depth on the EXISTING
  loader.** LFM2.5-2.6B extends the exact conv+GQA arch we serve
  ([Liquid blog](https://www.liquid.ai/blog/lfm2-5-8b-a1b) — same
  family; [LFM2 tech report](https://arxiv.org/html/2511.23404v1));
  tool-calling quality is the family's design target (96–98% tool-call
  at 350M fine-tuned [reported,
  Distill labs](https://www.distillabs.ai/blog/fine-tuning-liquids-lfm25-accurate-tool-calling-at-350m-parameters)).
  Rung = config dialect check (`layer_types` vs the v1
  `full_attn_idxs`), fixture, parity gate. The 8B-A1B MoE needs
  expert-routing bindings — only on product demand.
- **ADOPT (harness, cheap): LFM2.5 encoders for local semantics.**
  230M/350M bidirectional encoders, 8K ctx
  ([Liquid](https://www.liquid.ai/blog/lfm2-5-encoders)) — a local
  embedding lane for the harness's context tiers with zero egress.
  Needs a bidirectional-encoder forward (masking differs) — rung-sized.
- **CONSIDER, not now: KV-cache quantization/compression.** EACL 2026
  KV Pareto reports 68–78% memory cut at 1–3% loss
  ([aclanthology](https://aclanthology.org/2026.eacl-industry.9));
  ChunkKV (NeurIPS 2025) compresses semantically
  ([poster](https://neurips.cc/virtual/2025/poster/120181)). At 1–2B
  sizes our KV is tens of MB — memory is not binding [measured]; our
  2k decode degrades only ~20% without it. Revisit at 128K-ctx goals
  (LFM2.5-8B-A1B class).
- **REJECT (hard laws restated, unchanged): continuous batching**
  (B=1 products; the 2026 field's own note — hybrid models complicate
  batching/prefix caching — reinforces this,
  [r/LocalLLaMA SOTA thread](https://www.reddit.com/r/LocalLLaMA/comments/1vphr8u/sota_apple_silicon_inference_august_15_2026));
  **GGUF runtimes** (mlx-native kernels win on Apple Silicon — the
  ladder's floor math); **training/autodiff** (different product).
- **WATCH: cross-vendor and distributed MLX.** Experimental CUDA
  backend ([analysis](https://www.linkedin.com/pulse/silicon-rebellion-how-apples-mlx-quietly-rewriting-rules-deb-ljn7f))
  and WWDC26 distributed-inference session
  ([Apple](https://developer.apple.com/videos/play/wwdc2026/233)) —
  relevant to the phone+desktop join direction; no rung until a product
  asks. Apple's own M5/MLX benchmark writeup
  ([ML Research](https://machinelearning.apple.com/research/exploring-llms-mlx-m5))
  is the reference to re-check at hardware upgrade time.

## ecsai_harness application

The harness palette already declares the lanes
(`pkgs/xsoulspace_agentic_host/lib/src/model_palette.dart`): `laya`
(local decision, leads the decision order) and `mlx_local` (bounded
local generative, rides LAST — explicit casts and mechanical drafting
consumers only). What changes with this stack:

1. **mlx_local runtime swap (the big one, ADR-first):** the python
   mlx_lm serve (napbench p50 244–1105 ms) → the in-process engine
   behind the existing loopback wire. The pattern exists and is
   tested — `LayaQwenChatServer` (LoopbackJsonServer over
   NativeQwenTextEngine) and now the LFM2 engine; a
   `LayaLfm2ChatServer` is additive. First-token path drops from
   hundreds of ms to ~14–16 ms + 65–85 tok/s decode [measured], no
   python, no spawned process, no egress. The wire contract
   (`/health`, `POST /v1/chat/completions`) is unchanged, so the
   palette entry's consumers don't move.
2. **laya decision lane: unchanged.** 96.5 ms decisions, local, leads
   the order — the ladder already serves it natively.
3. **Mechanical drafting consumers:** the palette comment's promise
   becomes concrete — LFM2.5-1.2B (or 2.6B at the next rung) as the
   named cast for bounded generative work: summaries, drafting,
   classification inside harness actors, without egress.
4. **Local embeddings for context tiers:** LFM2.5 encoders (watch
   item) would let `context_grab`'s semantic tiers run without the
   hosted embedding dependency.
5. **Boundary law:** engine work stays in this repo; the harness
   consumes only the loopback wire contract — no new cross-repo
   coupling.

## Non-claims

- All [reported] numbers are vendor/community figures, not reproduced
  here; several search results carry future-dated or unverified claims
  and are cited as leads, not evidence.
- The M1 bench is one machine at one thermal state; same-run
  comparability only.
- No MoE, no MLA, no KV-quant work has been done — the corresponding
  rows are watch/consider, not capabilities.
