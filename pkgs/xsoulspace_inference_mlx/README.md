# xsoulspace_inference_mlx

A **local small generative text model** (MLX on Apple Silicon) bound as an
`xsoulspace_inference_core` `InferenceClient` — the text-generation sibling
of the laya local decision provider.

Two engines behind one wire (the engine-policy seam oka ADR-0039 proposes):

- **Native (primary)** — `native/mlx_text_native` wraps
  `ml-explore/mlx-swift-lm` (MLXLLM/MLXLMCommon) in a Swift dylib built by
  the package hook (the laya native-assets pattern). Served on loopback via
  `bin/mlx_serve_native.dart`; also usable fully in-process through
  `NativeMlxChatEndpoint`. Includes a cross-request KV prefix cache
  (verified trim, rebuild-on-misalignment) and EOS-correct stopping.
- **Python (fallback)** — `mlx_lm.server` on loopback, attach-only by
  default.

## Native vs Python — measured (2026-10-08, Apple M1, Qwen3-1.7B-4bit)

| metric | native (mlx-swift-lm) | Python (`mlx_lm.server`) |
| --- | --- | --- |
| model load (to serving) | **~1.3–1.7s** | ~2.4s (+ ~7s first request) |
| cold full-prefill request (849-tok prompt) | **~2.9s** | ~4.9s |
| warm repeated-prompt request | **p50 1366ms** (own prefix cache) | p50 1418ms (server prompt cache) |
| decode throughput | **~45 tok/s** | ~36 tok/s |
| draft (16-block, greedy) | 267B, identical bytes | 267B, identical bytes |

Native's prefix cache reuses the KV common prefix of the previous request
(trim-verified per layer, rebuild on misalignment) with EOS-correct
stopping — all three were paid-for bugs: the empty-suffix crash, rotating-
window drift symptoms, and `TokenIterator.next()` stopping only at the
token cap (the EOS check is the caller's job). KV-cache quantization
(`kv_bits: 8`) is supported per request: a memory lever, not a speed lever
at this context size.

Speculative decoding was implemented and then REMOVED (2026-10-08):
with a Qwen3-0.6B draft under Qwen3-1.7B on M1 it measured no net speedup,
and greedy outputs were not byte-lossless under the draft path in
mlx-swift-lm 3.32.3. Our drafts law requires determinism. Revisit only if
the library's temp-0 verify path is fixed or with a tuned MTP drafter
(the library ships `SpeculativeTokenIterator`; the git history holds the
working integration).

## Text-lane acceptance bench — napbench (2026-10-08, M1/16GiB)

`tool/napbench_text_lane.dart` measures the lane against the ADR 0051
acceptance table (cold prefill TTFT at 2k/4k/8k targets, decode tok/s
p50/p95, RSS). Cold = a fresh nonce per rep so the cross-request KV
prefix reuse never masks prefill; `--warm` measures the drafting-lane
shape; `--prefill-step/--unchunked` shape prefill. ONE MODEL PER
PROCESS — model succession plus repeated fresh-KV prefills contaminate
later numbers (observed: decode 45 → 7 tok/s when a second model loads
into the same process).

Observed (battery power, throttled; AC references from the morning
run above):

| model | cold prefill 1.4k/2.8k/5.5k tok | decode tok/s p50 | verdict |
| --- | --- | --- | --- |
| Qwen3-0.6B-4bit | 7.1s / 18.5s / 46.7s (~150 tok/s) | 30.1 | TTFT@4k ≤300ms **MISSED** ~60x |
| Qwen3-1.7B-4bit | 24.4s / 46.8s / 88.0s (~60 tok/s) | 3.5–6 (AC ref: ~45) | TTFT@4k **MISSED** ~150x |
| LFM2.5-1.2B-4bit | 21.9s / 32.4s / 39.9s (~80-165 tok/s) | 26.6 (AC ref: 37–66) | TTFT **MISSED**; decode ≥45 **MISSED** on battery, borderline on AC |

An independent python `mlx-lm` run (battery) prefilling 1135 tokens in
7.5s (~152 tok/s) matches the native lane — the numbers are the
machine's mlx speed, not a lane defect. Recorded learnings:

- **The ≤300ms@4k TTFT row was mis-calibrated** (like laya's ≤5 ms
  decision row): measured prefill is ~60-300 tok/s for these 4-bit
  models on M1, so 4k tokens costs 9-50 s. The row needs re-baselining
  in ADR 0051 — either ~100x worse targets or a different class of
  hardware.
- **Benchmarks must record power state.** On battery, macOS throttles
  sustained GPU work ~4-10x (decode 45 → 3.5 tok/s); CPU-only steps
  (chat template) throttle too. Re-baseline on AC before promoting any
  number.
- Prefill grows within a process across fresh-KV requests (13.8 →
  19.9 s for the same shape) — mlx allocator/wired-memory pressure is
  the suspected mechanism, not yet pinned.
- **Routing implication** (ADR 0051 ladder): long-prompt text workloads
  (harness 2k-8k shapes) are not locally viable on this hardware —
  route them to a mesh peer or remote; nap-draft-class short prompts
  (~100 tok, sub-second warm) stay local.

**Pure Dart.** This package needs NO Flutter for native FFI: `dart:ffi` +
native assets run under the plain Dart VM, and the native smoke test runs
under `dart test` (it skips under `flutter test` — flutter_tester blocks
on the blocking FFI bridge). Gate this package with:

```bash
dart analyze && dart test   # native smoke needs local Qwen3 weights; skips otherwise
```

## Shape

- `MlxServeRuntime` — the shared health-gated loopback serve skeleton
  (`xsoulspace_inference_local_serve`) with MLX defaults: attach to an
  already-running `mlx_lm.server`, or spawn it on miss (explicit opt-in),
  health deadline sized for a cold model load, honest readiness snapshots.
- `MlxLocalTextClient` — `InferenceClient` over the OpenAI-compatible chat
  wire (`/v1/chat/completions`). Plain `InferenceTask.text` only; greedy
  decoding by default; typed unavailable when detached.
- `FakeMlxChatServer` / `ScriptedMlxChatEngine` — pure-Dart wire fake on the
  shared `LoopbackJsonServer` skeleton; the whole client path is testable
  with no Python runtime and no model weights.
- `NapDraftPrompts` / `NapDraftRecord` / `NapDraftStore` — the nap-drafting
  contract: provenance-stamped drafts in a review-only sidecar queue.

## Hard laws

- **Derived only.** The model drafts summaries and annotations; it never
  writes raw records. Drafts apply only through the reviewer-run `nap`
  command — the same validated, provenance-linked write path the tool
  itself uses.
- **Nothing model-driven in any read path.** Wake/orient/find stay
  deterministic (ADR 0079). The drafts queue is a review worklist nothing
  reads to answer questions.
- **No egress.** Loopback only. The runtime never installs or downloads;
  the operator chooses the model and starts (or opts into spawning) the
  server.
- **Content-free diagnostics.** Wire events carry byte counts, statuses,
  and durations — never prompt text, memory records, or completions.

## Model choice — napbench verdict (2026-10-08, Apple M1, 4-bit)

Measured on the actual task (280-byte one-line summaries of 16-block /
2-block memory fixtures, same prompt and lane, faithfulness reviewed
against sources — refusal on uncertainty counts as PASS):

| model | license | p50 (16-block) | tok/s | faithfulness 16-block | 2-block |
| --- | --- | --- | --- | --- | --- |
| **Qwen3-1.7B-4bit** (primary) | Apache-2.0 | 1418ms | ~36 | **PASS** — all claims traceable, 0 invented (thinking mode OFF required) | **PASS** |
| LFM2.5-1.2B-Instruct-MLX-4bit | LFM Open v1.0 ($10M commercial cap) | 244–1105ms | ~37–66 | FAIL — invents names or drifts numbers under every prompt variant | near-miss |
| LFM2-700M-4bit | LFM Open v1.0 | 1260ms | ~100 | FAIL — ignores one-line/budget contract | PASS-ish |
| SmolLM3-3B-4bit | Apache-2.0 | 5264ms | ~24 | FAIL — degenerate repetition | invalid |

The primary ships nothing: weights are a local operator download
(`mlx-community/Qwen3-1.7B-4bit`) and never redistributed by this repo.
The provider package is model-agnostic — the checkpoint id travels in
configuration (`OPTMEM_MLX_MODEL` / `HARNESS_MLX_MODEL`) and MUST name
what the server actually serves (`mlx_lm.server` resolves an unknown
request model id as a Hugging Face repo at request time).

## Isolated native preparation

The build hook accepts `native_cache_root` through the root application's
cache-tracked `hooks.user_defines` for this package:

```yaml
hooks:
  user_defines:
    xsoulspace_inference_mlx:
      native_cache_root: /absolute/private/native-cache
```

The hook publishes into `<root>/mlx_text/native` instead of the default fleet
cache. Empty, relative or non-string roots refuse before native compilation.
Hook output assets and the resolving workspace's `.dart_tool/lib` are still
populated. This is a build destination setting; runtime loaders are unchanged.
Use the emitted bundle/assets for isolated execution. Custom environment
variables are filtered by the SDK hook runner; use this user-define instead.
