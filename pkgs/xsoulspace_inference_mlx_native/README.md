# xsoulspace_inference_mlx_native

The MLX-native engine host for
[xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core):
one Rust cdylib (statically linking the pinned MLX 0.32.2 + mlx-c sources),
one composition API, one binding table — and the model drivers that share it
(the laya decision op-chain, Qwen3, LFM2) with their Dart FFI clients,
OpenAI-compatible chat servers, and the unified `InferenceClient` binding.
Knows no product: products (`xsoulspace_inference_laya`, the harness text
lane) depend on this package; it depends on none of them ([ADR
0057](../../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md),
[ADR 0058](../../../docs/decisions/0058_native_engines_unified_inference_interface.md)).

**Running benches or perf gates? Read [POWER.md](POWER.md) first** — the
power laws (ADR 0061): sense/record/gate, never command; perf gates
assert only on AC..

## Model drivers

All drivers ride the same crate, dylib, and FFI surface
(`native/mlx_native`):

- **laya** — the `aac6fef/laya-mlx` decision op-chain (ModernBERT-large,
  typed `choice`/`score`/`noul` questions, calibrated probabilities in one
  forward pass), exposed through `NativeLayaDecisionEngine` and the
  `LayaDecisionEngine` seam.
- **qwen** — Qwen3 dense checkpoints (0.6B/1.7B, q4 default) with raw
  completion, parity fixtures against the python `mlx_lm` reference
  (`testdata/qwen3_06b_parity.json`), and `LayaQwenChatServer`.
- **lfm2** — LFM2/LFM2.5-Instruct (hybrid conv+attention, flat long-context
  curve) with the fixture-gated chat template + EOS discipline and
  `LayaLfm2ChatServer`. The 2.6B checkpoint rides the same driver
  (`Lfm2ChatTemplateVariant.lfm25_26b` — its template opens the think
  block at the generation prompt; special-token ids resolve from the
  checkpoint's own tokenizer, never guessed across checkpoints).

## Using the engines — three consumption paths

1. **In-process, unified interface** (ADR 0058): a loaded engine binds as
   an `InferenceClient` — the same interface every remote and local
   provider in the monorepo answers to:

   ```dart
   final client = await MlxNativeTextClient.loadLfm2(); // or loadQwen()
   final result = await client.infer(
     InferenceRequest(prompt: '…', systemPrompt: '…', maxTokens: 320),
     toolRegistry: registry, // both casts render tools into their template
   );
   ```

   The client IS the bench's winning cell: template render + EOS stop +
   clean answer text. No raw mode (raw cells are a bench reproduction);
   greedy decode only (a non-zero temperature lands in
   `InferenceResult.warnings`, never silently pretended). Requires a
   process that can load native assets (`dart run`/`dart test`; NOT
   `dart compile exe` — AOT drops them).

2. **Wire** — `dart run tool/serve_text.dart [--engine lfm2|qwen]
   [--port N] [--raw] [--thinking]` serves the OpenAI-compatible loopback
   (`GET /health`, `POST /v1/chat/completions`); any HTTP client attaches
   (curl, the harness `mlx_local` attach-only client, other languages).
   The default cast is the measured production one (LFM2.5, template+EOS).

3. **Harness / decision product** — the daemon's laya decision lane and
   the `MlxLocalTextClient` wire client; consumers import THIS package
   directly (the laya barrel re-export shim was dropped, ADR 0057 R3).

## The assetId

The cdylib registers as a code asset under
`package:xsoulspace_inference_mlx_native/mlx_native` (built by
`hook/build.dart`; crate, dylib, and C symbols share the `mlx_native` base
name). First build needs cargo, cmake, and the Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`); without them the package
still analyzes, its scripted tests pass, and the golden test skips with
that reason. Weights: `LAYA_MODEL_DIR` or `~/.cache/xsoulspace/laya-mlx`;
text snapshots resolve from the HF hub cache (`QWEN3_SNAPSHOT` /
`LFM2_SNAPSHOT` env or explicit dir) — the runtime never downloads
anything by itself. The historical Swift + mlx-swift host remains
documented in git history and stays the reference route for iOS
(ml-explore/mlx#3915).

## Bench and gates

- `tool/serve_text.dart` — the production-line serve binary.
- `tool/model_bench_suite.dart` — the lane bench (chat, decompression,
  swe, tools, laya-decision) over any OpenAI-compatible endpoint or the
  in-process native line; scorecards land in `bench/` and are the palette's
  cited evidence (thresholds pinned in ADR 0057 once two runs exist).
- `tool/test_fresh.sh` — the golden parity cycle (63/63 @ 0.0 / 1.5e-8).

## The composition API (ADR 0054) — every forward is a declared plan

All three drivers ride the same declared-plan executor and binding table,
and the plan path is the DEFAULT for all of them (opt-outs are A/B switches,
not legacy paths): laya's decision op-chain (R1; `LAYA_COMPILE` additionally
fuses it — opt-in, default flip DECLINED 2026-10-11: the first traced call
per shape costs seconds and break-even is 150+ decisions/shape), Qwen3
decode + prefill (R2/R5, `LAYA_QWEN_PLAN=0` opt-out), and LFM2's hybrid
short-conv/GQA forward (R6, `LAYA_LFM2_PLAN=0` opt-out) — attention KV
buffers and the sliding conv state are both functional plan outputs.

Parity law, mechanically enforced:

- `tests/lfm2_plan_parity.rs` / `tests/qwen_plan_parity.rs` — the plan path
  is bit-identical to the imperative walk on the live model (decode logit
  bits; prefill caches including conv states across a cache-growth boundary),
  and the fixtures pass under BOTH routing modes. R6's gate caught a real
  store-back divergence (full buffers vs trimmed views) before it shipped.
- `tests/plan_op_sweep.rs` — every op kind the drivers submit is
  bit-identical between the direct binding dispatch and the plan executor
  (23 cells, model-realistic shapes/dtypes). A new Op variant adds a cell.
- Plan reviews read JSON: `LAYA_LFM2_PLAN_DUMP` / `LAYA_QWEN_PLAN_DUMP`
  write the per-call plan; `LAYA_DEBUG_DUMP` keeps stage dumps aligned
  between the paths.

Recorded serving non-claims (open items, not regressions): no cross-request
KV common-prefix reuse (fresh cache per generate — the retired Swift engine
had it) and no token streaming.

## Native tool-call transport

Qwen clients default to `ToolCallSyntax.qwenJson`: complete checkpoint JSON
envelopes normalize into `InferenceResponse.toolCalls`, with raw output and
source spans retained in metadata. Missing registries, unknown tool names,
malformed/truncated calls and fenced examples produce named failures.
Constructors accept an explicit `toolSyntax` for a qualified finetune; this
selects the decoder, not a new tokenizer/chat template. The LFM default has
no qualified production decoder for its Python-like signature format and
refuses those envelopes as `tool_syntax_unsupported`. The permissive bench
parser is not an execution parser.

Without explicit messages, native clients use the existing core
`SituationMessagesCodec` to render only the request's projected fragments.
Explicit messages remain authoritative. Qwen tool-result turns use its
fixture-gated renderer; LFM maps explicit tool turns to user turns and warns.
The deterministic transport tests prove normalization and observation
rendering, not useful model coding or real-model acceptance.

## Prepared native CLI closure

Developer preparation uses `tool/prepare_native_cli.dart` with four arguments:
compiler, an already prepared SDK package config, output directory, and Dart
entry point. It calls the existing SDK `build cli` and native build hook under
`runBounded`; it does not download weights or create another engine build loop.

Dart 3.13.2 CLI bundles the native code asset but omits the hook's Metal data
asset. The helper finds the producer receipt inside that exact SDK profile,
requires a complete image match, and packages only its colocated Metal file.
For macOS SDK relocation, it reproduces install-ID rewriting and ad-hoc signing
on a private copy and compares every transformed byte; a UUID or filename is
not sufficient. Missing, mismatched or conflicting producer closures refuse.
`bundle/native_closure.json` retains original and relocated image hashes,
producer receipt hash, and Metal hash.

`tool/native_runtime_preflight.dart` is a no-model diagnostic entry point:
it performs harmless NFC through the native asset, uses `dladdr` to report the
actual loaded image, and checks colocated Metal. This qualifies preparation
and identity only. It does not load weights, execute GPU model inference,
qualify other SDKs, or establish coding acceptance. Product integration should
prepare/bundle this closure automatically rather than expose setup commands.
