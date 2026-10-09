# xsoulspace_inference_laya — agent notes

The laya decision-model PRODUCT: `LayaServeRuntime` (attach-only loopback
runtime) + `LayaLocalDecisionProvider` (the core `DecisionProvider`).
Everything engine-shaped (the cdylib, drivers, decision seam, parity
fixtures) lives in `xsoulspace_inference_mlx_native` and is imported from
there directly — the R2 re-export shim was dropped at R3 ([ADR
0057](../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md)).

## Gates

```bash
just analyze-one xsoulspace_inference_laya
just test-one xsoulspace_inference_laya
```

## Laws

- No engine code lands here. If a change touches the cdylib, the FFI
  clients, the chat servers, or the decision seam, it belongs in the
  engine package.
- The runtime never spawns or downloads by default (`spawnOnMiss` is the
  explicit opt-in); a detached runtime surfaces as a typed
  `DecisionUnavailable`, never a socket error.
