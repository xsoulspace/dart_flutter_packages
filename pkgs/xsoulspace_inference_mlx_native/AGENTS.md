# xsoulspace_inference_mlx_native — agent notes

The MLX-native engine host: one Rust cdylib (`native/mlx_native`),
one composition API, one binding table, and the model drivers that share
it (laya decision op-chain, Qwen3, LFM2/LFM2.5 incl. the 2.6B variant).
Knows no product — products depend on this package ([ADR 0057](../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md),
[ADR 0058](../../docs/decisions/0058_native_engines_unified_inference_interface.md)).

## Gates

Dart build hooks hang under the agent sandbox — run dart/cargo with the
sandbox disabled.

```bash
just analyze-one xsoulspace_inference_mlx_native
just test-one xsoulspace_inference_mlx_native          # dart suite (loads the dylib)
(cd native/mlx_native && cargo test --release)          # rust parity battery
tool/test_fresh.sh                                      # golden cycle: 63/63 @ 0.0 / 1.5e-8
```

The `l0_ops_run_and_are_dispatch_cheap` gate flakes under thermal load —
re-run standalone before calling it a failure.

## Laws

- Every new architecture = Rust port with a parity fixture (venv-recorded,
  provenance in the file). Never weaken an oracle.
- The runtime NEVER downloads. Checkpoints resolve from the HF hub cache
  or explicit dirs.
- Parity-fixture streams run with EOS stop OFF (byte-identical oracles);
  the chat surfaces opt in.
- Special-token ids resolve from the checkpoint's own tokenizer, never
  carried across checkpoints: the lfm2 FFI exposes them
  (`mlx_native_lfm2_special_ids` — the 1.2B's 7/2 vs the 2.6B's
  124900/124895); the Qwen3 family shares one tokenizer across sizes
  (ids pinned by the parity fixtures).
- Bench numbers are non-claims until recorded with power state (AC/battery);
  speed comparisons are interleaved same-process (cross-run is
  thermal-contaminated).
