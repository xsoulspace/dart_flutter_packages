# Publishing Guide

This document is a release checklist for the modular logger stack.

## Packages

Publish in this order:

1. `xsoulspace_logger`
2. `xsoulspace_logger_io`
3. `xsoulspace_logger_triage`
4. `xsoulspace_logger_universal_storage`
5. `xsoulspace_logger_flutter`

## Preconditions

- Update package versions consistently.
- Ensure each package has:
  - `README.md`
  - `CHANGELOG.md`
  - `LICENSE`
  - pubspec metadata (`homepage`, `repository`, `issue_tracker`, `documentation`, `topics`)
- Ensure no package uses `path:` dependencies in `pubspec.yaml`.

## Validation

For each package, run:

```bash
dart pub get
dart analyze
dart test
```

For Flutter package:

```bash
flutter pub get
flutter analyze
flutter test
```

Also run:

```bash
dart pub publish --dry-run
```

(or `flutter pub publish --dry-run` for Flutter package)

## Publishing

Run in each package directory:

```bash
dart pub publish
```

or

```bash
flutter pub publish
```

## Post-publish

- Verify package pages on pub.dev.
- Tag release in git with matching version(s).
- Update repo-level release notes.
