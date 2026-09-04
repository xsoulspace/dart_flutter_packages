# pkgs/xsoulspace_inference_apple_foundation: Agent Working Agreement

Apple Foundation Models (`SystemLanguageModel`) backend for
`xsoulspace_inference_core` on macOS 26+. **Pure Dart, FFI-only** — no
Flutter plugin surface (ADR 0012 / P5): a SwiftPM-built bridge dylib
(`libxs_fm_bridge.dylib`, compiled by `hook/build.dart`) is loaded via the
path-based loader in `lib/src/native_bridge/library_loader.dart`.

## Purpose

Expose Apple's on-device Foundation Models as a provider-agnostic
`InferenceClient` so the agent harness (`xsoulspace_agentic_harness`) can use
it interchangeably with hosted providers. One transport:

1. **FFI** — `dart:ffi` C-ABI bridge; serves headless CLIs and compiled
   binaries without a Flutter engine.

## R7 daemon surface (ADR 0023)

| Path | Role |
| --- | --- |
| `bin/harnessd.dart` | The long-lived ACP agent: `--backend`, `--profile meaning`, `--scripted`, `--remote-mover` (MODEL-LESS daemon — pi's model decides via `session/propose_move`), `--workspace <path>` (single-instance lock + unix socket + idle-exit), `--idle-exit-minutes`. AFM-first default on macOS. |
| `lib/src/harness_acp_backend.dart` | Per-workspace persistent worlds; meaning tree never snapshotted; `loadSession` restore; deny-by-default permissions; real cancellation; escalation capped `min(3+rounds, 9)`; unique tool-call ids; tool results streamed MID-TURN; the remote mover (`AcpMoveProposing`). |
| `lib/src/coding_agent_runner.dart` | The runner core — meaning-profile surface (`repo_etl`/`meaning_zoom`/`meaning_impact`/`edit_symbol`/`run`, zero fs tools; `run` is ALLOWLISTED to the convention commands). The run-graded fs arm is LEGACY-HOST-ONLY. |

Gates: `test/harnessd_r7c_test.dart`, `test/harnessd_remote_mover_test.dart`,
`test/meaning_profile_overhead_test.dart`. Rows + transcripts:
`../../xsoulspace_agentic_harness/docs/agent/results_r7.md` (the
`r7_daemon_transcript.txt` referenced by older rows lives in
`xsoulspace_agentic_harness/benchmark/runs/` — superseded by
`r7_edit_surface_transcript.txt` and `r7_warm_attach_transcript.txt`).

## Layout

| Path | Role |
| --- | --- |
| `lib/xsoulspace_inference_apple_foundation.dart` | Barrel → `NativeClient` (the `InferenceClient`). |
| `lib/src/native_bridge/` | FFI bindings, path loader, client impl. |
| `macos/.../Sources/` | Swift core: `AppleFoundationBridge.swift`, `DartSchemaMaterializer.swift` (+ `Package.swift`). The old plugin registrar was removed with the Flutter transport. |
| `hook/build.dart` | Native-assets hook: compiles the Swift dylib and registers it as a code asset. |
| `bin/stress/` | Scenario definitions + parse/render for the stress CLI. |

## Entrypoints

| Command | Purpose |
| --- | --- |
| `bin/apple_foundation_cli.dart` | FFI smoke: probe / ask / tool. |
| `bin/stream_smoke.dart` | TTFT streaming smoke. |
| `bin/agent.dart` | Everyday REPL over harness CLI SDK. |
| `bin/coding_suite_*.dart` | Thin suite/probe launchers over harness benchmark API. |
| `bin/stress_cli.dart` | Scenario stress runs (`list` / `run --scenario=multi_actor [--json]`). |

## Guardrails

- Do **not** change `xsoulspace_inference_core` public API or add
  `xsoulspace_agentic_harness` engine code here.
- Keep the Swift core shared by every consumer of the dylib — do not fork
  bridge logic per binary.
- No Flutter dependencies may return without reopening ADR 0012.

## Validation

```bash
cd pkgs/xsoulspace_inference_apple_foundation
flutter pub get && flutter analyze && flutter test   # unit layer (no device)
```

On-device smokes (macOS 26+, Apple Intelligence):

```bash
dart run bin/apple_foundation_cli.dart list
dart run bin/stream_smoke.dart
dart run bin/stress_cli.dart list
```
