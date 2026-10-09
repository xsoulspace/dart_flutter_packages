# xsoulspace_inference_local_serve

Shared composition core for **local model servers** on this machine:
health-gated loopback runtimes, managed process lifecycle, one-shot health
probes, and a pure-Dart loopback wire-server skeleton.

Consumers:

- `xsoulspace_inference_laya` — the local System One decision server
  (`laya-serve` on loopback).
- `xsoulspace_inference_mlx` — a local small text model behind an
  OpenAI-compatible chat server on loopback (the native in-process
  engine via `mlx_serve_native.dart`; python `mlx_lm.server` is the
  retired reference server, spawn escape hatch only).

Both compose this core instead of growing second one-offs; the extraction
keeps the laya public API byte-stable.

## What the core owns

- `LocalServeRuntime` — the one readiness concern: is a server answering on
  the health endpoint? Attach-only by default; spawning a process is an
  explicit `spawnOnMiss` composition decision. Honest local snapshots
  (getters never probe), a health deadline with early-exit detection, and
  content-free diagnostics (configuration and outcome facts only — never
  prompt text or model output).
- `ManagedServeProcess` / `ServeProcessStarter` — spawn lifecycle, injectable
  for tests; the runtime kills only what it spawned.
- `LocalHealthProbe` — one-shot loopback probe (any answering status below
  500 counts as alive; a 404 still proves the socket).
- `LoopbackJsonServer` — bind/route/auth/decode/containment plumbing for
  pure-Dart wire fakes and servers (the laya System One server and the MLX
  chat fake are routes on this skeleton).

Request-level deadlines are a wire-adapter concern (each client carries its
own timeout); the runtime owns the health deadline only.

## Laws

- Loopback only. Nothing here installs, downloads checkpoints, or sends a
  byte off this machine.
- Readiness is honest: a detached runtime surfaces as a typed unavailable,
  never a fake ready.
- Diagnostics never carry content.

## Native build cache destinations

The separate `native_asset_cache.dart` entrypoint selects a directory without
creating it. Laya and MLX hooks share it to validate their cache-tracked
`native_cache_root` user-define. An explicit absolute root isolates preparation
outputs; omitting it preserves the existing fleet cache. It configures build
publication paths, not runtime library resolution or acceptance.
