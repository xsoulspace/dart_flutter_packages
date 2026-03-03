# xsoulspace_platform_crazygames

CrazyGames adapter for unified runtime.

## Provided capabilities

- `IdentityCapability`
- `FriendsCapability`
- `LeaderboardWriteCapability`

## Notes

- Non-web environments return `PlatformInitResult.notAvailable`.
- Anonymous users map to `currentPlayer == null`.
- Ads are separated into `xsoulspace_platform_crazygames_ads`.
