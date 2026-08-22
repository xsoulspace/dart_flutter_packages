# pkgs/xsoulspace_inference_apple_foundation: Agent Working Agreement

Apple Foundation Models (`SystemLanguageModel`) implementation of
`xsoulspace_inference_core` for macOS 26+. Part of the `dart_flutter_packages`
workspace; Skill Steward is adopted at the workspace root.

## Purpose

Expose Apple's on-device Foundation Models as a provider-agnostic
`InferenceClient`, so the agent harness in `xsoulspace_inference_core` can use
it interchangeably with other providers. Two runtime surfaces share one Swift
core:

1. **Flutter plugin** (existing) — `MethodChannel` transport for Flutter apps.
2. **Native CLI / ACP** (target) — `dart:ffi` C-ABI bridge for pure-Dart hosts
   with no Flutter engine. Enables a standalone CLI and an ACP stdio server
   that IDEs like Zed can drive as an agent subprocess.

## North Star Impact

This package serves the workspace North Star by making the *model* a
replaceable reasoning primitive: the harness does the heavy lifting, the
provider is swappable. Native FFI + ACP support is classified as **`applies`**
— it extends the existing provider boundary without changing repo center or
the canonical agent API in `xsoulspace_inference_core`.

Guardrails:

- Do **not** change `xsoulspace_inference_core` public API. This package
  implements it; changes to contracts happen upstream.
- Keep the Swift core (`FoundationModelsBridge`, `DartSchemaMaterializer`)
  shared between both transports — do not fork logic per surface.
- The C-ABI bridge must not leak Flutter types into its signature.

## Where Things Live

| Path | Role |
| --- | --- |
| `lib/src/apple_foundation_inference_client.dart` | `InferenceClient` impl (transport-agnostic entry). |
| `lib/src/dynamic_scheme/foundation_api.dart` | Flutter MethodChannel transport. |
| `lib/src/native_bridge/` | FFI transport (planned): `@Native` decls + loader. |
| `macos/.../Sources/` | Swift core: bridge, schema materializer, plugin registrar. |
| `bin/` | Native CLI entrypoint (planned). |
| `acp/` | ACP stdio server surface (planned; standalone library lives in mcp_flutter). |
| `example/lib/main_stress_cli.dart` | Flutter-hosted stress CLI (current workaround). |

## Validation

```bash
cd pkgs/xsoulspace_inference_apple_foundation
flutter pub get
flutter analyze
flutter test
```

Native CLI smoke (requires macOS 26+ with Apple Intelligence):

```bash
dart run bin/apple_foundation_cli.dart list
dart run bin/apple_foundation_cli.dart run --scenario=multi_actor --json
```

ACP conformance smoke:

```bash
echo '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}' \
  | dart run acp/bin/acp_server.dart
```

## Docs To Update

- Public usage changes → `README.md`.
- Transport/bridge internals → this file and `lib/src/dynamic_scheme/README.md`.
- Durable decisions about the native bridge → ADR at repo root `docs/decisions/`.
