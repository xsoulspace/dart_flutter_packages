# xsoulspace_steamworks_raw

Raw Steamworks FFI package for Dart/Flutter desktop.

## What This Package Contains

- Dynamic library resolution and loading (`SteamRawLibraryLoader`).
- Runtime-safe symbol lookup layer (`SteamRawBindings`).
- Generated low-level binding surface from `steam_api_flat.h`.
- Generator tooling with lock/snapshot/diff/check workflow.

## SDK Setup Prerequisites

1. Install Steamworks SDK locally from Valve.
2. Set `STEAMWORKS_SDK_PATH` to your SDK root path.
3. Set `STEAMWORKS_SDK_VERSION` (or create `<sdk>/steamworks_sdk_version.txt`) to match `tool/upstream_lock.json`.
4. Run `just generate`.

Important: this package does **not** redistribute Steamworks headers or binaries.

## Platform Binary Placement

Provide Steam runtime libraries in your app/runtime location or via explicit `librarySearchPaths` in wrapper config.

- Windows: `steam_api64.dll` (or `steam_api.dll`)
- macOS: `libsteam_api.dylib`
- Linux: `libsteam_api.so`

## Local Dev With `steam_appid.txt`

For local desktop runs, place `steam_appid.txt` near your executable and set your test app id there.

## Generator Commands

- `just generate`: regenerate bindings/snapshot/diff.
- `just generate-check`: fail if committed generated files are stale.
- `just verify`: run generate-check + analyze + tests.

## Known Failure Modes And Diagnostics

- SDK lock mismatch: update `STEAMWORKS_SDK_VERSION`/SDK path or explicitly bump lock.
- Missing library: check search paths and binary names for your platform.
- Missing symbol: Steam client/runtime version may not match the locked SDK.
