# xsoulspace_platform_discord

Discord adapter for unified `PlatformRuntime`.

## Provided capabilities

- `IdentityCapability`
- `FriendsCapability`
- `InviteCapability` (optional via config toggle)
- `FeedShareCapability` (optional via config toggle)
- `DiscordRawCapability` (optional raw API escape hatch)

## Notes

- Supports bridge/global probing and optional bridge autoload hook.
- Runs OAuth `authorize -> backend exchange -> authenticate` when `oauthGateway` is configured.
- Returns `PlatformInitResult.notAvailable` when Discord Activity context is missing.
