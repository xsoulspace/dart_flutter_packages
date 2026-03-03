# Publishing Checklist (`xsoulspace_steamworks`)

## Dependency Readiness

1. `xsoulspace_steamworks_raw` release is already published.
2. `pubspec.yaml` pins correct raw version.
3. Remove local path overrides before publish (`pubspec_overrides.yaml` should not
   override non-dev dependencies during release validation).

## Verification

```bash
just verify
```

Example integration test:

```bash
cd example
flutter test integration_test -d macos
```

If running local checks before raw is published, use a temporary
`pubspec_overrides.yaml` path override and delete it before publishing.

## Pub.dev Dry Run

```bash
flutter pub publish --dry-run
```

## Publish

```bash
flutter pub publish
```

## Release Order

Publish this package **after** `xsoulspace_steamworks_raw`.
