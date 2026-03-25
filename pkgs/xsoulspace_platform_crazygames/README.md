# xsoulspace_platform_crazygames

CrazyGames adapter for unified runtime.

## Provided capabilities

- `IdentityCapability`
- `FriendsCapability`
- `LeaderboardWriteCapability`

## Notes

- Non-web environments return `PlatformInitResult.notAvailable`.
- Config supports SDK probe/autoload fields:
  `expectedSdkGlobal`, `sdkUrl`, `autoLoadSdk`, `sdkScriptLoader`, `sdkInjected`.
- Anonymous users map to `currentPlayer == null`.
- Ads are separated into `xsoulspace_platform_crazygames_ads`.
