# Deployment Runbook (Internal Registry v1)

This runbook describes what we deploy and how to deploy it in production.

The registry architecture has two parts:

1. **Publish pipeline (write path)**: GitHub Actions workflow `.github/workflows/registry_publish.yml`.
2. **Gateway runtime (read path)**: container from `registry/gateway/` serving hosted-pub-compatible read endpoints.

The registry is **read-only at runtime**. Package publication is done only by CI.

## What Gets Deployed

### 1) Metadata and archives

- Metadata (`api/package-names.json`, `api/packages/*.json`) is pushed to the `registry-index` branch.
- Package archives (`<package>-<version>.tar.gz`) are uploaded to GitHub Releases.
- Packages with `publish_to: none` are excluded by tooling.

### 2) Gateway service

- Service code: `registry/gateway/server.py`
- Container: `registry/gateway/Dockerfile`
- Required endpoints:
  - `GET/HEAD /api/package-names`
  - `GET/HEAD /api/packages/<package>`
  - `GET/HEAD /api/packages/<package>/versions/<version>`
  - `GET/HEAD /packages/<package>/versions/<version>.tar.gz`
  - `GET /healthz`
  - `GET /readyz`

## Prerequisites

- Repository admin access for GitHub Actions and branches.
- A public HTTPS hostname for the registry (example: `https://pub.xsoulspace.dev`).
- Runtime target for the gateway container (VM/K8s/container platform).
- DNS and TLS configured for the registry hostname.
- Ability to deploy/pull gateway images.

## One-Time Setup

### A) Configure repository and branch

1. Ensure workflow `.github/workflows/registry_publish.yml` is enabled.
2. Ensure `registry-index` branch exists (workflow can initialize it if missing).
3. Ensure repository has permissions to create/update releases and push `registry-index`.

### B) Deploy gateway service

Build and run (example):

```bash
docker build -t xs-registry-gateway registry/gateway

docker run -d --restart unless-stopped \
  --name xs-registry-gateway \
  -p 8080:8080 \
  -e REGISTRY_INDEX_BASE_URL=https://raw.githubusercontent.com/<org>/<repo>/registry-index \
  -e GITHUB_REPOSITORY=<org>/<repo> \
  -e CACHE_DIR=/var/cache/registry-gateway \
  -e CACHE_TTL_SECONDS=300 \
  -e UPSTREAM_TIMEOUT_SECONDS=10 \
  -e UPSTREAM_RETRY_COUNT=1 \
  -e UPSTREAM_RETRY_BACKOFF_SECONDS=0.2 \
  xs-registry-gateway
```

Put your reverse proxy/load balancer in front of port `8080` and terminate TLS there.

### C) Validate gateway readiness

```bash
curl -fsS https://<registry-host>/healthz
curl -fsS https://<registry-host>/readyz
```

Expected payload:

```json
{"status":"ok"}
```

## Publish/Release Flow (How New Versions Go Live)

### Automatic path

- Push to `main`/`master` with package `version:` updates in `pkgs/*/pubspec.yaml`.
- Workflow `registry_publish` runs automatically.

### Manual path

- Trigger `registry_publish` with `workflow_dispatch`.
- Optional inputs:
  - `registry_base_url` (default `https://pub.xsoulspace.dev`)
  - `index_branch` (default `registry-index`)

### What CI enforces

The workflow runs these hard gates before publishing metadata:

1. Existing repo gates (`docs-check`, `storage-release-g6`, `platform-sdk-verify`).
2. Registry tests (`just registry-test`).
3. Fresh registry build and strict validation.
4. Deterministic rebuild check (metadata + archive hash match).
5. Gateway smoke tests for one stable and one prerelease package.
6. Release upload plus downloaded-asset SHA256 verification.

If any gate fails, publication stops and metadata branch is not updated.

## Post-Deploy Verification

Run after each publish/deploy:

```bash
curl -fsS https://<registry-host>/api/package-names | jq .
curl -fsS https://<registry-host>/api/packages/<package> | jq '.latest.version'
curl -fsSI https://<registry-host>/packages/<package>/versions/<version>.tar.gz
```

Archive endpoint should return `302` with a GitHub Releases `Location` URL.

## Rollback

If a bad publish or deployment happens:

1. Remove incorrect release assets/tags from GitHub Releases (if needed).
2. Reset `registry-index` to last known-good commit and push.
3. Redeploy previous gateway image version.
4. Re-run verification checks (`/healthz`, `/readyz`, metadata endpoint, archive redirect).

## Operations and SLO Targets

- Availability target: **99.9% monthly** for read endpoints.
- Metadata freshness target: **<= 15 minutes** after successful publish workflow.

Recommended checks:

- Alert on `/readyz` failures.
- Alert on sustained `5xx` rate from gateway.
- Monitor workflow failures for `registry_publish`.

## Local Preflight (Before Production Changes)

From repo root:

```bash
just registry-test
just registry-build-index
just registry-validate
just registry-smoke build/registry stable
just registry-smoke build/registry prerelease
```
