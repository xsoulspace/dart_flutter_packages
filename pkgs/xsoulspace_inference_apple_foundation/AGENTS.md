# pkgs/xsoulspace_inference_apple_foundation: Agent Working Agreement

Apple Foundation Models (`SystemLanguageModel`) backend for
`xsoulspace_inference_core` on macOS 26+. **Pure Dart, FFI-only** — no
Flutter plugin surface: a SwiftPM-built bridge dylib
(`libxs_fm_bridge.dylib`, compiled by `hook/build.dart`) is loaded via the
path-based loader in `lib/src/native_bridge/library_loader.dart`.

## Purpose

Expose Apple's on-device Foundation Models as a provider-agnostic
`InferenceClient`. One transport:

1. **FFI** — `dart:ffi` C-ABI bridge; serves headless CLIs and compiled
   binaries without a Flutter engine.

## Boundary (ADR 0036)

This package owns the FFI transport and the native-asset build. It does
not depend on the harness. The daemon, coding runner, ACP host policy, and
the AFM composition root (`appleFoundationBinding`, `bin/harnessd.dart`)
live in `~/xs/ecsai_harness` (`xsoulspace_agentic_afm` and
`xsoulspace_agentic_host`).

## Layout

| Path | Role |
| --- | --- |
| `lib/xsoulspace_inference_apple_foundation.dart` | Barrel → `AppleFoundationNativeClient` (the `InferenceClient`). |
| `lib/src/native_bridge/` | FFI bindings, path loader, client impl. |
| `macos/.../Sources/` | Swift core: `AppleFoundationBridge.swift`, `DartSchemaMaterializer.swift` (+ `Package.swift`). |
| `hook/build.dart` | Native-assets hook: compiles the Swift dylib and registers it as a code asset. |
| `bin/stream_smoke.dart` | TTFT streaming smoke against this client. |

## Guardrails

- Do not change `xsoulspace_inference_core`'s public API from this package.
- Do not add a dependency on `xsoulspace_agentic_harness`, host, or workspace.
- Keep the Swift core shared. Do not fork bridge logic per binary.
- No Flutter plugin surface returns without a new ADR.

## Validation

From repository root: `just check xsoulspace_inference_apple_foundation`.

On-device smoke (macOS 26+, Apple Intelligence):

```bash
dart run bin/stream_smoke.dart
```

```bash
LIVE=0 sh tool/check_bridge_swift.sh
sh tool/check_bridge_swift.sh
```

`LIVE=0` compiles the Swift tests without a model call. A green analyze
does not prove a live Foundation Model session.
