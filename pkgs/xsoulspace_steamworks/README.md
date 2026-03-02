# xsoulspace_steamworks

Manual-safe Steamworks wrapper for Dart/Flutter desktop.

## v1 Scope

- Lifecycle: initialize/shutdown/restart check.
- Callback pumping: auto (default) and manual.
- Services: `User`, `Friends`, `Stats`, `Achievements`.
- Event stream for lifecycle and callback runtime events.

## SDK Setup Prerequisites

1. Add `xsoulspace_steamworks_raw` + `xsoulspace_steamworks` to your project.
2. Install Steamworks SDK locally.
3. Configure generation in `xsoulspace_steamworks_raw` with `STEAMWORKS_SDK_PATH`.
4. Provide Steam runtime library files locally (do not bundle Valve SDK artifacts inside published package archives).

## Platform Binary Placement

Runtime `steam_api` library must be discoverable.

- Windows: `steam_api64.dll` / `steam_api.dll`
- macOS: `libsteam_api.dylib`
- Linux: `libsteam_api.so`

Use `SteamInitConfig.librarySearchPaths` when binaries are outside default locations.

## Local Dev With `steam_appid.txt`

Place `steam_appid.txt` near your executable for desktop local runs.
Use Valve test app ids for smoke validation.

## Example

See `example/lib/main.dart` for init, callback pumping, stats, and achievements flow.

## Known Failure Modes And Diagnostics

- `SteamInitErrorCode.noSteamClient`: Steam is not running or client is unavailable.
- `SteamInitErrorCode.versionMismatch`: Steam runtime and SDK lock are incompatible.
- `SteamInitErrorCode.restartRequired`: process must be launched via Steam.
- `SteamRawErrorCode.libraryNotFound`: runtime `steam_api` library not found.

## Important Boundary

This wrapper intentionally keeps callback routing, async completion mapping, and pointer safety in manual runtime code.
Raw symbol coverage is generator-first, but runtime safety remains hand-maintained.
