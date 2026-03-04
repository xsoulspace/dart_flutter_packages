# Publishing Guide

This repository contains multiple packages with cross-package dependencies.
Use this guide to publish them to pub.dev with minimal friction.

## Prerequisites

- Flutter SDK installed (`flutter --version`)
- Dart SDK installed (`dart --version`)
- Authenticated to pub.dev (`dart pub token add https://pub.dev`)
- Clean git state for the package you are publishing (recommended)
- No active `dependency_overrides` in `pubspec_overrides.yaml` for the package being published

## Validate documentation and metadata

From repo root:

```bash
just platform-sdk-verify
just docs-check
just storage-release-g6
```

This verifies every package has:

- `README.md`
- `CHANGELOG.md`
- `LICENSE`
- Universal Storage target apps resolve local package paths only via
  `pubspec_overrides.yaml` (no inline Universal Storage path overrides in
  app `pubspec.yaml`)
- Platform SDK beta release-set packages have no local path dependencies in
  `pubspec.yaml`

## Run package dry-runs

Single package:

```bash
just publish-dry-run <package_name>
```

All packages:

```bash
just publish-dry-run-all
```

Both `publish-dry-run` commands are gated by `storage-release-g6` and fail on
blocking findings. Gate sequence:

1. `storage-path-audit`
2. `clone-guard-audit`
3. analyzer (errors-only)
4. tests
5. `StorageReleaseGateEvaluator` artifact

If a package contains `pubspec_overrides.yaml`, temporarily remove/rename it before running publish dry-run.

Unified Platform SDK beta release-set dry-run:

```bash
just platform-sdk-publish-dry-run
```

By default this command uses `--ignore-warnings` so local
`pubspec_overrides.yaml` monorepo path wiring does not block dry-run.
Set `IGNORE_WARNINGS=0` to enforce warning-free dry-runs in a clean release
workspace:

```bash
IGNORE_WARNINGS=0 bash tool/platform_sdk_publish_dry_run.sh
```

## Recommended publish order (Unified Platform SDK beta wave)

All changed release-set packages use `-beta.1` prerelease versions and should be published in topological order:

1. Wrappers and low-level deps:
   - `xsoulspace_vkplay_js`
   - `xsoulspace_ysdk_games_js`
   - `xsoulspace_crazygames_js`
   - `xsoulspace_discord_js`
2. Interfaces and runtime/bridges:
   - `xsoulspace_platform_core_interface`
   - `xsoulspace_platform_social_interface`
   - `xsoulspace_platform_gamification_interface`
   - `xsoulspace_platform_multiplayer_interface`
   - `xsoulspace_platform_foundation`
   - `xsoulspace_platform_purchases_bridge`
   - `xsoulspace_platform_ads_bridge`
   - `xsoulspace_platform_monetization_bridge`
3. Base adapters:
   - `xsoulspace_platform_steam`
   - `xsoulspace_platform_vkplay`
   - `xsoulspace_platform_yandex_games`
   - `xsoulspace_platform_crazygames`
   - `xsoulspace_platform_discord`
4. Plugin adapters:
   - `xsoulspace_monetization_yandex_games`
   - `xsoulspace_monetization_ads_crazygames`
   - `xsoulspace_platform_yandex_games_purchases`
   - `xsoulspace_platform_crazygames_ads`
5. Optional server APIs (same beta wave when docs rely on them):
   - `xsoulspace_vkplay_server_api`
   - `xsoulspace_discord_server_api`

Notes:

- Publish foundational dependencies first, then rerun dry-runs for dependents.
- Keep local development path wiring in `pubspec_overrides.yaml` only.

## Publish command

Run from each package directory:

```bash
flutter pub publish
```

or for pure Dart packages:

```bash
dart pub publish
```
