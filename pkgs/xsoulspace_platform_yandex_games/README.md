# xsoulspace_platform_yandex_games

Yandex Games adapter for unified runtime.

## Provided capabilities

- `IdentityCapability`
- `LeaderboardReadCapability`
- `LeaderboardWriteCapability`
- `StatsReadCapability`
- `StatsWriteCapability`
- `MultiplayerSessionCapability`

## Notes

- Non-web environments return `PlatformInitResult.notAvailable`.
- Purchases are separated into `xsoulspace_platform_yandex_games_purchases`.
