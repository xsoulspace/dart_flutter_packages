# Unified Platform SDK Production Guide

This guide covers production setup for the unified SDK release scope:
Steam, VK Play, Yandex Games, CrazyGames, and Discord.

## Runtime setup by priority

Register adapters in desired priority order and start `PlatformRuntime`:

```dart
final runtime = PlatformRuntime(
  factories: <PlatformAdapterFactory>[
    SteamPlatformFactory(config: steamConfig, priority: 0),
    VkPlayPlatformFactory(config: vkConfig, priority: 1),
    YandexGamesPlatformFactory(config: yandexConfig, priority: 2),
    CrazyGamesPlatformFactory(config: crazyConfig, priority: 3),
    DiscordPlatformFactory(config: discordConfig, priority: 4),
  ],
  initOptions: const PlatformInitOptions(
    missingCapabilityBehavior: MissingCapabilityBehavior.strict,
  ),
);

await runtime.start();
```

Factories are sorted by `priority` before startup attempts.

## Strict vs permissive startup behavior

- `strict`
  - runtime tries all candidate adapters by priority.
  - runtime throws `PlatformException(initFailed)` when none initialize.
  - no no-op fallback activation.
- `permissive`
  - runtime still tries all candidates by priority.
  - runtime activates fallback no-op client if none initialize.
  - optional fallback capabilities can be supplied to runtime.

Runtime emits startup diagnostics events:
- `runtime.startup.adapterAttempt` for each unsupported/failed attempt.
- `runtime.startup.failed` when strict mode ends with no active adapter.

## Optional capability access patterns (`require` vs `maybe`)

- Use `require<T>()` for mandatory product flows.
  - throws `MissingPlatformCapabilityException` when unsupported.
- Use `maybe<T>()` for optional/feature-flagged flows.
  - returns `null` when unsupported.

Example:

```dart
final identity = runtime.require<IdentityCapability>();
final invite = runtime.maybe<InviteCapability>();
```

## Monetization plugin wiring

Base adapters stay monetization-agnostic. Add plugins only where needed:

- Yandex purchases: `xsoulspace_platform_yandex_games_purchases`
- CrazyGames ads: `xsoulspace_platform_crazygames_ads`

Plugin behavior:
- capability is attached only when provider init succeeds.
- optional plugin failures keep base platform active unless configured fatal.

## Backend gateway usage (Discord/VK flows)

Backend gateways are required for server-mediated flows:

- VK Play:
  - `VkPlaySocialGateway` for invite/feed-share.
- Discord:
  - `DiscordOAuthGateway` for `authorize -> exchange -> authenticate`.

Production recommendations:
- validate gateway responses server-side.
- apply anti-replay/state validation for OAuth exchanges.
- keep invite/share endpoints idempotent.

## Migration for teams using direct package APIs

Incremental adoption path:

1. keep existing direct SDK wrapper calls in place.
2. introduce `PlatformRuntime` with one adapter (current platform only).
3. migrate read paths first (`IdentityCapability`, `FriendsCapability`).
4. migrate write paths next (leaderboards/stats/invite/share).
5. add optional plugin capabilities (purchases/ads) behind `maybe<T>()`.
6. switch startup to `strict` in pre-prod; use `permissive` only where fallback is explicitly acceptable.
