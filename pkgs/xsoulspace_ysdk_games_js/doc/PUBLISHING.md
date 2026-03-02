# Publishing Guide

This package is intended for publication on `pub.dev`.

## Release checklist

1. Ensure upstream typings lock is correct in `tool/upstream_lock.json`.
2. Regenerate bindings:

   ```bash
   just generate
   ```

3. Run full verification:

   ```bash
   just verify
   ```

4. Run pub dry-run:

   ```bash
   dart pub publish --dry-run
   ```

5. Update `CHANGELOG.md` with release notes and upstream typings version.
6. Bump `version` in `pubspec.yaml`.
7. Publish:

   ```bash
   dart pub publish
   ```

## Upstream typings bump

Use:

```bash
just generate-bump <version>
```

This updates lock metadata, regenerates files, and refreshes API snapshot/diff
artifacts.
