# Registry Gateway

Minimal hosted-pub-compatible read gateway for the internal Dart registry.

## Endpoints

- `GET /api/packages/<package>`
- `HEAD /api/packages/<package>`
- `GET /api/packages/<package>/versions/<version>`
- `HEAD /api/packages/<package>/versions/<version>`
- `GET /api/package-names`
- `HEAD /api/package-names`
- `GET /packages/<package>/versions/<version>.tar.gz`
- `HEAD /packages/<package>/versions/<version>.tar.gz`
- `GET /healthz`
- `GET /readyz`

`/api/*` responses are fetched from the generated metadata branch/repo and cached
on disk. Metadata responses include `ETag` and `Cache-Control: public, max-age=60`;
clients may send `If-None-Match` to receive `304 Not Modified` when unchanged.
Archive requests validate the package/version against metadata and then return a
`302` redirect to the configured archive source. On transient upstream failures
the gateway serves stale cached metadata when available.

## Environment

- `REGISTRY_INDEX_BASE_URL`: Raw HTTP base for generated metadata.
  Example: `https://raw.githubusercontent.com/xsoulspace/dart_flutter_packages/registry-index`
- `GITHUB_REPOSITORY`: Required when the redirect template uses `{github_repo}`.
- `ARCHIVE_REDIRECT_TEMPLATE`: Redirect target template.
  Default: `https://github.com/{github_repo}/releases/download/{tag}/{asset}`
- `CACHE_DIR`: On-disk cache path.
- `CACHE_TTL_SECONDS`: Metadata cache TTL.
- `UPSTREAM_TIMEOUT_SECONDS`: Upstream fetch timeout in seconds.
- `UPSTREAM_RETRY_COUNT`: Retry count for transient upstream failures.
- `UPSTREAM_RETRY_BACKOFF_SECONDS`: Backoff between retries.
- `PORT`: HTTP port.

Available template variables:

- `{package}`
- `{version}`
- `{tag}`
- `{asset}`
- `{github_repo}`

## Local smoke test

```bash
docker build -t xs-registry-gateway registry/gateway

docker run --rm -p 8080:8080 \
  --env REGISTRY_INDEX_BASE_URL=https://raw.githubusercontent.com/xsoulspace/dart_flutter_packages/registry-index \
  --env GITHUB_REPOSITORY=xsoulspace/dart_flutter_packages \
  xs-registry-gateway
```

Use `/healthz` for process liveness and `/readyz` when you need an
upstream-aware readiness signal.
