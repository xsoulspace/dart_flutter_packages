# xsoulspace_steamworks_raw

Raw Steamworks FFI bindings and runtime loading for Dart/Flutter desktop.

## Legal and Distribution Notice

- This package **does not** ship Valve proprietary Steamworks SDK headers or binaries.
- Consumers must provide SDK files locally for generation and runtime binaries for execution.
- Keep Steamworks SDK licensing obligations in your own project and release process.

## Package Scope

`xsoulspace_steamworks_raw` provides:

- `SteamRawLibraryLoader`
- `SteamRawBindings`
- `SteamRawException`
- Generated symbols from `steam_api_flat.h` (functions/types/structs/enums)

It does **not** provide high-level callback routing, async completion registry, or lifecycle guardrails.
Those are intentionally manual and live in `xsoulspace_steamworks`.

## Platform Support

Desktop only:

- Windows
- macOS
- Linux

## Install

```yaml
dependencies:
  xsoulspace_steamworks_raw: ^0.1.0
```

## Runtime Binary Placement

Provide the Steam runtime library where the app can load it:

- Windows: `steam_api64.dll` (or `steam_api.dll`)
- macOS: `libsteam_api.dylib`
- Linux: `libsteam_api.so`

## Local SDK Setup for Generation

1. Install Steamworks SDK locally.
2. Export `STEAMWORKS_SDK_PATH` to the SDK root.
3. Ensure SDK version matches `tool/upstream_lock.json` (`sdkVersion` + header hash).
4. Run generation.

```bash
just generate
```

## Generator Pipeline

The raw generator (`tool/generate.dart`) performs:

1. shim header generation (`tool/steam_api_flat_shim.h`)
2. `ffigen` generation via `tool/ffigen.yaml`
3. deterministic post-processing
4. API snapshot emission (`tool/api_snapshot.json`)
5. API diff emission (`tool/api_diff.json`)
6. stale-file verification in `--check` mode

Commands:

- `just generate`
- `just generate-check`
- `just analyze`
- `just test`
- `just verify`

Useful env vars:

- `STEAMWORKS_SDK_PATH`
- `STEAMWORKS_SDK_VERSION`
- `STEAMWORKS_MOCK_FFIGEN_OUTPUT` (tests/CI fixture mode)
- `STEAMWORKS_FFIGEN_EXEC` (custom ffigen executable)

## Known Failure Modes

- Lock mismatch: SDK version/hash differs from `tool/upstream_lock.json`
- Missing runtime library: `SteamRawErrorCode.libraryNotFound`
- Missing symbol: `SteamRawErrorCode.symbolNotFound`

## Publishing

See [PUBLISHING.md](./PUBLISHING.md) for the release checklist.
