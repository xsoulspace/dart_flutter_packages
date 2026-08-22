# ADR 0001: Native FFI bridge + ACP server for Apple Foundation

- Status: Accepted
- Date: 2026-08-22
- North Star impact: `applies`

## Context

`xsoulspace_inference_apple_foundation` currently reaches Swift Foundation
Models through a Flutter `MethodChannel`. This forces every consumer — including
the stress CLI (`example/lib/main_stress_cli.dart`) — to run inside a Flutter
engine. Two consequences:

1. No pure-Dart CLI is possible; the "CLI" today is a `flutter build macos`
   binary with `--dart-entrypoint-args`.
2. The package cannot act as an [ACP](https://agentclientprotocol.com) agent
   subprocess, which IDEs (Zed, and others) launch as a plain stdio process.

Dart FFI speaks only the C ABI. The existing Swift core
(`FoundationModelsBridge`, `DartSchemaMaterializer`) is transport-agnostic in
logic but its entrypoints are Flutter-plugin-shaped.

## Decision

1. **Add a C-ABI bridge** alongside the MethodChannel transport. Swift exposes
   `@_cdecl` functions; Dart binds via `dart:ffi`
   (`DynamicLibrary.open` first, migrating to `@Native(assetId:)` +
   build hooks when stable). The tool-call round-trip uses a **callback
   pointer** (option A): Dart registers a `NativeFunction` callback that Swift
   invokes when the model requests a tool, mirroring the existing
   `ToolInvoker` protocol.
2. **Keep one Swift core**, two thin transports. Do not fork
   `FoundationModelsBridge` or `DartSchemaMaterializer` per surface.
3. **Implement the ACP server as a standalone Dart library** hosted in the
   `mcp_flutter` repo (sibling to `mcp_server_dart`), not inside this package.
   This package provides the agent brain (`HarnessLoop`, `ModelRouter`,
   `ToolRegistry`) that the ACP library drives.
4. **Do not change `xsoulspace_inference_core` public API.** The FFI surface
   implements the existing `InferenceClient` contract unchanged.

## Consequences

- Pure-Dart CLI becomes possible (`bin/apple_foundation_cli.dart`).
- Zed/IDE integration via ACP stdio without a Flutter engine.
- The C header, Swift shim, and Dart `@Native` declarations must stay in sync;
  codegen (extending the dormant `static_compile/` experiment) is the planned
  follow-up, not a prerequisite.
- `DynamicLibrary.codeAsset` remains experimental (`@Since('3.14')`);
  `DynamicLibrary.open` + path resolution (the proven
  `SteamRawLibraryLoader` pattern) is the initial loader.

## Non-goals

- Changing the canonical agent API or harness semantics (upstream repo).
- Replacing the MethodChannel transport for Flutter apps.
- Remote/HTTP ACP transports (v1 spec: stdio only).
