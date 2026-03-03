# Unified Platform Runtime Architecture

## Layers

1. `xsoulspace_platform_core_interface`: base runtime and error contracts.
2. Capability interface packages:
   - gamification
   - social
   - multiplayer
   - purchases bridge
   - ads bridge
3. `xsoulspace_platform_foundation`: runtime selection and fallback behavior.
4. Adapter packages:
   - Steam
   - Yandex Games
   - CrazyGames
   - VK Play skeleton
5. Optional feature plugins:
   - `xsoulspace_platform_yandex_games_purchases`
   - `xsoulspace_platform_crazygames_ads`

## Resolution Flow

1. Runtime sorts factories by `priority`.
2. Runtime probes each factory via `isSupportedEnvironment()`.
3. Runtime initializes first successful client.
4. If none initialize successfully, runtime activates no-op fallback client.
5. Required capabilities are enforced according to strict/permissive mode.

## Missing Capability Policy

- `strict`: throw `MissingPlatformCapabilityException`.
- `permissive`: try fallback/no-op capability where available.

## Adapter Principle

Adapters wrap existing source-of-truth packages (`xsoulspace_steamworks`, `xsoulspace_ysdk_games_js`, `xsoulspace_crazygames_js`) and do not replace their internals.

## Dependency Modularity

- Base adapters do not hard-depend on monetization plugins.
- Purchases/ads are attached by wrapper plugin packages.
- Purchases bridge is pure Dart; ads bridge is Flutter-only.
- `xsoulspace_platform_monetization_bridge` remains as compatibility export.
- Apps can install only the base adapters and capability interface packages they use.
