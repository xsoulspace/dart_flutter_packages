# xsoulspace_inference_mlx_native

The MLX-native engine host for
[xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core):
one Rust cdylib (statically linking the pinned MLX 0.32.2 + mlx-c sources),
one composition API, one binding table — and the model drivers that share it
(the laya decision op-chain, Qwen3, LFM2) with their Dart FFI clients and
OpenAI-compatible chat servers. Knows no product: products
(`xsoulspace_inference_laya`, the harness text lane) depend on this package;
it depends on none of them ([ADR
0057](../../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md)).

## Model drivers

All drivers ride the same crate, dylib, and FFI surface
(`native/laya_rust`):

- **laya** — the `aac6fef/laya-mlx` decision op-chain (ModernBERT-large,
  typed `choice`/`score`/`noul` questions, calibrated probabilities in one
  forward pass), exposed through `NativeLayaDecisionEngine` and the
  `LayaDecisionEngine` seam.
- **qwen** — Qwen3 dense checkpoints (0.6B/1.7B, q4 default) with raw
  completion, parity fixtures against the python `mlx_lm` reference
  (`testdata/qwen3_06b_parity.json`), and `LayaQwenChatServer`.
- **lfm2** — LFM2/LFM2.5-Instruct (hybrid conv+attention, flat long-context
  curve) with the fixture-gated chat template + EOS discipline and
  `LayaLfm2ChatServer`.

The shared composition API (`LayaTypedQuestion`, decision-plan op-chain) is
the input encoding every driver consumes; `LayaByteLevelTokenizer` is the
pure-Dart prompt-encoding helper.

## The assetId

The cdylib registers as a code asset under
`package:xsoulspace_inference_mlx_native/laya_native` (built by
`hook/build.dart`; the crate/dylib base name stays `laya_native` this rung —
recorded debt, ADR 0057). First build needs cargo, cmake, and the Metal
Toolchain (`xcodebuild -downloadComponent MetalToolchain`); without them the
package still analyzes, its scripted tests pass, and the golden test skips
with that reason. Weights: `LAYA_MODEL_DIR` or `~/.cache/xsoulspace/laya-mlx`
— fetch the checkpoints from Hugging Face; the runtime never downloads
anything by itself. The historical Swift + mlx-swift host remains documented
in git history and stays the reference route for iOS (ml-explore/mlx#3915).

Serve the production line: `dart run tool/serve_text.dart` (or
`tool/model_bench_suite.dart` for the three-lane bench; `tool/test_fresh.sh`
for the golden cycle).
