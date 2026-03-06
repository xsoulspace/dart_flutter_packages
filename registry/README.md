# Registry

Unified home for the internal hosted-pub registry implementation.

Deployment runbook: `deploy/README.md`.

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

## Quick Usage

From repository root:

```bash
just registry-rewrite-hosted
just registry-build-index
just registry-validate
just registry-test
just registry-smoke build/registry stable
just registry-smoke build/registry prerelease
```

Gateway docs and local smoke-test commands:

- `registry/gateway/README.md`
