# xsoulspace_platform_foundation

Runtime orchestration layer for unified platform adapters.

## Main API

- `PlatformRuntime`
- `PlatformAdapterFactory`
- `PlatformStartResult`
- `NoopPlatformClient`

## Runtime behavior

- Activates one platform client by `priority` (`firstAvailable` strategy).
- Supports strict/permissive missing-capability behavior.
- Includes no-op fallback client.
- No-op feature capabilities are provided by optional plugin packages.

## Capability Matrix (Phase 1)

| Capability | Steam | Yandex Games | CrazyGames | VK Play |
| --- | --- | --- | --- | --- |
| Identity | yes | yes | yes | yes |
| Friends | yes | no | yes | yes |
| Invite | no | no | no | optional |
| Feed Share | no | no | no | optional |
| Achievement Read | yes | no | no | no |
| Achievement Write | yes | no | no | no |
| Stats Read | yes | yes | no | no |
| Stats Write | yes | yes | no | no |
| Stats Sync | yes | no | no | no |
| Leaderboard Read | no | yes | no | no |
| Leaderboard Write | no | yes | yes | no |
| Multiplayer Session | no | yes | no | no |
| Purchases (optional plugin) | no | plugin | no | no |
| Ads (optional plugin) | no | no | plugin | no |

## Migration Guide

1. Keep existing direct wrapper/provider usage for current apps.
2. Add platform adapters and initialize `PlatformRuntime`.
3. Replace direct platform calls with capability access:
   - `runtime.require<T>()` for required features.
   - `runtime.maybe<T>()` for optional features.
4. Migrate one feature area at a time (identity, stats, leaderboards, monetization).
5. Keep strict mode in development and permissive mode only where no-op fallback is acceptable.

See [Architecture](doc/architecture.md). Integration runtime example is in
`pkgs/xsoulspace_platform_yandex_games/example/runtime_integration_example.dart`.
