# xsoulspace_platform_steam

Steam adapter for unified runtime.

## Provided capabilities

- `IdentityCapability`
- `FriendsCapability`
- `AchievementReadCapability`
- `AchievementWriteCapability`
- `StatsReadCapability`
- `StatsWriteCapability`
- `StatsSyncCapability`

## Usage

```dart
final factory = SteamPlatformFactory(
  config: const SteamPlatformConfig(appId: 480),
);
```
