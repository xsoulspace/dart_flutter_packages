# Publishing Checklist (`xsoulspace_steamworks_raw`)

## Before Version Bump

1. Confirm `tool/upstream_lock.json` matches intended SDK baseline.
2. Re-run generator against that SDK.
3. Verify no proprietary SDK artifacts are tracked in git.

## Verification

```bash
STEAMWORKS_SDK_PATH=/path/to/SteamworksSDK just verify
```

For CI fixture-mode verification:

```bash
STEAMWORKS_SDK_PATH=test/fixtures/fake_sdk \
STEAMWORKS_MOCK_FFIGEN_OUTPUT=test/fixtures/mock_ffigen_output.dart \
just verify
```

## Pub.dev Dry Run

```bash
flutter pub publish --dry-run
```

## Publish

```bash
flutter pub publish
```

## Release Order

Publish this package **before** `xsoulspace_steamworks`.
