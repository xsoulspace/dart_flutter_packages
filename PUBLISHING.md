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

## Recommended publish order (monetization chain)

These packages depend on each other and must be published in order:

1. `xsoulspace_monetization_interface`
2. `xsoulspace_monetization_ads_interface`
3. `rustore_billing_api`
4. `xsoulspace_monetization_ads_foundation`
5. `xsoulspace_monetization_google_apple`
6. `xsoulspace_monetization_huawei`
7. `xsoulspace_monetization_rustore`
8. `xsoulspace_monetization_ads_yandex`
9. `xsoulspace_monetization_foundation`

Notes:

- `xsoulspace_monetization_*` implementation packages can fail `--dry-run` until the required interface versions are published.
- Publish core interfaces first, then rerun dry-run for dependent packages.

## Publish command

Run from each package directory:

```bash
flutter pub publish
```

or for pure Dart packages:

```bash
dart pub publish
```
