# Publishing Guide

This repository now publishes internal packages through a GitHub-backed hosted
registry flow instead of a runtime `dart pub publish` endpoint.

Deployment runbook: `deploy/README.md`.

## Registry v1 layout

- Package metadata lives on the `registry-index` branch under `api/`.
- Package archives are built from tracked package files and uploaded to GitHub
  Releases as `<package>-<version>.tar.gz`.
- The Docker gateway in `registry/gateway/` serves hosted-pub-compatible
  read endpoints and redirects archive downloads to the release assets.

Default registry URL:

```bash
https://pub.xsoulspace.dev
```

## Local authoring flow

Before opening a release PR:

```bash
just docs-check
just storage-release-g6
just platform-sdk-verify
just registry-test
just registry-rewrite-hosted
just registry-validate
```

What these commands do:

1. Validate package docs and existing release gates.
2. Rewrite internal package dependencies in `pkgs/*/pubspec.yaml` to explicit
   hosted dependencies that point at the internal registry.
3. Build `build/registry/` with publishable packages only (`publish_to: none`
   packages are excluded) and produce:
   - `api/packages/<package>.json`
   - `api/package-names.json`
   - `archives/<package>-<version>.tar.gz`
   - `release-manifest.json`
4. Validate hosted dependency rewrites, metadata payloads, and archive SHA256
   values, and fail on stale extra artifacts.

Path-based internal dependencies are rewritten to the current target package
version because there is no version constraint to preserve.

## CI publish flow

`.github/workflows/registry_publish.yml` handles publication.

On `main`/`master` pushes or manual dispatch it:

1. Detects packages whose `version:` changed.
2. Runs the existing repo gates (`docs-check`, `storage-release-g6`,
   `platform-sdk-verify`).
3. Runs registry tooling tests, deterministic rebuild verification, and gateway
   smoke tests.
4. Builds package archives and regenerates hosted metadata.
5. Uploads changed package archives to GitHub Releases using the tag format
   `<package>-v<version>`.
6. Verifies each uploaded release asset matches the local archive SHA256.
7. Pushes generated metadata to the `registry-index` branch.

The workflow does not expose a hosted publish API. GitHub Actions is the write
path in v1.

## Consumer dependency format

Direct internal dependencies should use explicit hosted syntax:

```yaml
dependencies:
  xsoulspace_foundation:
    hosted:
      name: xsoulspace_foundation
      url: https://pub.xsoulspace.dev
    version: ^0.4.0
```

External dependencies continue to resolve from `pub.dev`.

## Gateway deployment

Build and run the gateway from `registry/gateway/`:

```bash
docker build -t xs-registry-gateway registry/gateway

docker run --rm -p 8080:8080 \
  --env REGISTRY_INDEX_BASE_URL=https://raw.githubusercontent.com/xsoulspace/dart_flutter_packages/registry-index \
  --env GITHUB_REPOSITORY=xsoulspace/dart_flutter_packages \
  xs-registry-gateway
```

The gateway provides:

- `GET /api/packages/<package>`
- `GET /api/packages/<package>/versions/<version>`
- `GET /api/package-names`
- `GET /packages/<package>/versions/<version>.tar.gz`
- `GET /healthz`
- `GET /readyz`

## Fallback

If the registry is unavailable, direct internal dependencies can be pinned to
Git refs temporarily while the metadata branch or gateway is restored.

## Rollback

If a publish must be reverted:

1. Remove the affected release asset/tag when archive bytes should no longer be served.
2. Reset the `registry-index` branch to the previous known-good commit.
3. Redeploy the previous gateway container image if the runtime itself changed.

## Production Targets

- Availability target: 99.9% monthly for read endpoints.
- Metadata freshness target: within 15 minutes of a successful publish run.
