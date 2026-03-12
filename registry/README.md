# Registry

Unified home for the internal hosted-pub registry implementation.

Deployment runbook: `DEPLOY.md`.

## Pillars

1. Single source of truth
   All registry tooling and runtime gateway code live under `registry/`.

2. Deterministic metadata and archives
   `registry/tools` generates reproducible package metadata and release archives
   from tracked package content, while excluding packages marked
   `publish_to: none`.

3. Stable command surface
   Repository-facing recipe names stay stable (`registry-rewrite-hosted`,
   `registry-build-index`, `registry-validate`) while script paths are standardized
   to `dart registry/tools/<script>.dart`.

4. Read-only gateway runtime
   `registry/gateway` serves hosted-pub-compatible read APIs and redirects archive
   downloads to release assets; CI remains the write path.

## Layout

- `registry/tools/`: Dart scripts for rewrite, index build, and validation.
- `registry/gateway/`: Python gateway runtime (`server.py`, `Dockerfile`,
  `.env.example`).

## Quick start

**Consumers (use internal packages):** Add the hosted URL to your dependency (one-time per package). List packages and versions with `just registry-list` or `just registry-list versions=true`; add a dependency with `just registry-add <target_package> <internal_package> [version]` (e.g. `just registry-add my_app xsoulspace_foundation ^0.4.0`). Or paste the hosted block into `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_foundation:
    hosted:
      name: xsoulspace_foundation
      url: https://pub.xsoulspace.dev
    version: ^0.4.0
```

**Authors (publish):** Before opening a release PR, run `just registry-release-preflight`. If it passes, push; CI will publish changed versions. Bump a package version with `just registry-bump <package> <version>`.

## Quick Usage

From repository root:

```bash
just registry-rewrite-hosted
just registry-build-index
just registry-validate
just registry-test
just registry-release-preflight   # full local pre-publish checklist
just registry-list                 # list packages (from build/registry)
just registry-list versions=true   # include latest versions
just registry-smoke build/registry stable
just registry-smoke build/registry prerelease
```

Gateway docs and local smoke-test commands:

- `registry/gateway/README.md`
