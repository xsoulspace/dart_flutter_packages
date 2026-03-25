# xsoulspace_platform_vkplay

VK Play adapter for the unified `PlatformRuntime`.

## Capabilities

- `IdentityCapability`
- `FriendsCapability`
- `InviteCapability` (optional, via backend gateway)
- `FeedShareCapability` (optional, via backend gateway)
- `VkPlayRawCapability` (optional raw API escape hatch)

## Config highlights

- SDK probe defaults to global `iframeApi`.
- Supports optional SDK script autoload (`sdkUrl` + `sdkScriptLoader`).
- Supports optional backend gateway injection for invite/share flows.
