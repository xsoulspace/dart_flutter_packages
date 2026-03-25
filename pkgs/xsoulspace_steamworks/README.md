# xsoulspace_steamworks

High-level Steamworks wrapper for Dart/Flutter desktop, built on `xsoulspace_steamworks_raw`.

## Legal and Distribution Notice

- This package does **not** redistribute Steamworks SDK headers or Valve binaries.
- You must provide Steam runtime binaries locally in your app environment.
- Mobile/web are out of scope and throw `UnsupportedError`.

## v1 Scope

- lifecycle: init/shutdown/restart checks
- callback pumping: auto (`16ms`) and manual (`runCallbacksOnce`)
- services: `User`, `Friends`, `Stats`, `Achievements`
- event stream for lifecycle/callback/async runtime events

## Install

```yaml
dependencies:
  xsoulspace_steamworks: ^0.1.0
```

`xsoulspace_steamworks_raw` is a transitive dependency and pinned by this wrapper.

## Quick Start

```dart
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

final client = SteamClient();

final init = await client.initialize(
  const SteamInitConfig(
    appId: 480,
    autoPumpCallbacks: true,
    callbackInterval: Duration(milliseconds: 16),
  ),
);

if (!init.success) {
  throw Exception('Steam init failed: ${init.errorCode} ${init.message}');
}

final loggedOn = client.user.isLoggedOn;
final steamId = client.user.steamId;
final persona = client.friends.personaName;

await client.stats.requestCurrentStats();
client.achievements.setAchievement('ACH_WIN_ONE_GAME');
await client.stats.storeStats();

await client.shutdown();
```

## Initialization Options

`SteamInitConfig` fields:

- `appId` (required)
- `autoPumpCallbacks` (default `true`)
- `callbackInterval` (default `16ms`, max `100ms`)
- `librarySearchPaths` (optional)
- `enableVerboseLogs` (default `false`)

## Runtime Binary Placement

Runtime must be able to load:

- Windows: `steam_api64.dll` / `steam_api.dll`
- macOS: `libsteam_api.dylib`
- Linux: `libsteam_api.so`

Use `librarySearchPaths` when binaries are outside default executable/current dirs.

## Local Dev (`steam_appid.txt`)

When launching a local debug build outside Steam, create `steam_appid.txt` next to
the executable and put your AppID inside (for example `480` for local smoke
workflows).

Without this file, Steam API initialization may fail even when Steam is running.

## Event Model

`SteamClient.events` emits:

- `SteamLifecycleEvent`
- `SteamCallbackEvent`
- `SteamAsyncCallResolvedEvent`
- `SteamAsyncCallTimeoutEvent`
- `SteamErrorEvent`

## Example App

See `example/lib/main.dart`.

Run example integration test (fake native backend):

```bash
cd example
flutter test integration_test -d macos
```

Change device for your platform (`-d windows` or `-d linux`).

## Failure Diagnostics

Common init failures:

- `SteamInitErrorCode.noSteamClient`
- `SteamInitErrorCode.versionMismatch`
- `SteamInitErrorCode.restartRequired`
- `SteamInitErrorCode.libraryLoadFailed`

## Manual Boundary (Intentional)

The wrapper keeps callback routing, `SteamAPICall_t` completion matching, and pointer/buffer safety in explicit manual runtime code. Raw symbol generation remains generator-first in the raw package.

## Publishing

See [PUBLISHING.md](./PUBLISHING.md).
