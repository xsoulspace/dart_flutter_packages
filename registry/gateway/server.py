import hashlib
import json
import os
import pathlib
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional, Tuple


def _normalize_url(value: str) -> str:
    return value.rstrip("/")


def _int_env(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return int(value)


def _float_env(name: str, default: float) -> float:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return float(value)


class Config:
    def __init__(self) -> None:
        self.host = os.environ.get("HOST", "0.0.0.0")
        self.port = _int_env("PORT", 8080)
        self.index_base_url = _normalize_url(os.environ["REGISTRY_INDEX_BASE_URL"])
        self.cache_dir = pathlib.Path(
            os.environ.get(
                "CACHE_DIR",
                str(pathlib.Path(tempfile.gettempdir()) / "xs-registry-gateway-cache"),
            )
        )
        self.cache_ttl_seconds = _int_env("CACHE_TTL_SECONDS", 300)
        self.upstream_timeout_seconds = _float_env("UPSTREAM_TIMEOUT_SECONDS", 10.0)
        self.upstream_retry_count = _int_env("UPSTREAM_RETRY_COUNT", 1)
        self.upstream_retry_backoff_seconds = _float_env(
            "UPSTREAM_RETRY_BACKOFF_SECONDS", 0.2
        )
        self.github_repository = os.environ.get("GITHUB_REPOSITORY", "")
        self.archive_redirect_template = os.environ.get(
            "ARCHIVE_REDIRECT_TEMPLATE",
            "https://github.com/{github_repo}/releases/download/{tag}/{asset}",
        )

        if "{github_repo}" in self.archive_redirect_template and not self.github_repository:
            raise SystemExit(
                "GITHUB_REPOSITORY is required when ARCHIVE_REDIRECT_TEMPLATE "
                "uses {github_repo}."
            )

        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._validate_cache_dir()
        self._validate_redirect_template()

    def metadata_url(self, package_name: str) -> str:
        return f"{self.index_base_url}/api/packages/{package_name}.json"

    def package_names_url(self) -> str:
        return f"{self.index_base_url}/api/package-names.json"

    def archive_redirect_url(self, package_name: str, version: str) -> str:
        tag = f"{package_name}-v{version}"
        asset = f"{package_name}-{version}.tar.gz"
        return self.archive_redirect_template.format(
            package=package_name,
            version=version,
            tag=tag,
            asset=asset,
            github_repo=self.github_repository,
        )

    def _validate_cache_dir(self) -> None:
        probe = self.cache_dir / ".write-probe"
        probe.write_text("ok")
        if probe.read_text() != "ok":
            raise SystemExit(f"Cache directory is not readable: {self.cache_dir}")
        probe.unlink(missing_ok=True)

    def _validate_redirect_template(self) -> None:
        try:
            self.archive_redirect_template.format(
                package="pkg",
                version="1.0.0",
                tag="pkg-v1.0.0",
                asset="pkg-1.0.0.tar.gz",
                github_repo=self.github_repository,
            )
        except KeyError as error:
            raise SystemExit(
                f"ARCHIVE_REDIRECT_TEMPLATE references unknown placeholder: {error}"
            ) from error


class Cache:
    def __init__(self, cache_dir: pathlib.Path, ttl_seconds: int) -> None:
        self._cache_dir = cache_dir
        self._ttl_seconds = ttl_seconds

    def get(self, key: str, *, allow_stale: bool) -> Tuple[Optional[bytes], str]:
        body_path = self._body_path(key)
        meta_path = self._meta_path(key)
        if not body_path.exists() or not meta_path.exists():
            return None, "miss"

        try:
            metadata = json.loads(meta_path.read_text())
        except json.JSONDecodeError:
            return None, "invalid"

        fetched_at = metadata.get("fetched_at_epoch")
        if not isinstance(fetched_at, (int, float)):
            return None, "invalid"

        if time.time() - float(fetched_at) > self._ttl_seconds:
            if allow_stale:
                return body_path.read_bytes(), "stale"
            return None, "stale"

        return body_path.read_bytes(), "fresh"

    def put(self, key: str, body: bytes) -> None:
        self._body_path(key).write_bytes(body)
        self._meta_path(key).write_text(
            json.dumps({"fetched_at_epoch": time.time()})
        )

    def _body_path(self, key: str) -> pathlib.Path:
        return self._cache_dir / f"{key}.body"

    def _meta_path(self, key: str) -> pathlib.Path:
        return self._cache_dir / f"{key}.json"


class UpstreamNotFound(Exception):
    pass


class UpstreamUnavailable(Exception):
    pass


class RegistryGateway(BaseHTTPRequestHandler):
    server_version = "xs-registry-gateway/1.1"

    config: Config
    cache: Cache

    def do_GET(self) -> None:
        self._handle_request(head_only=False)

    def do_HEAD(self) -> None:
        self._handle_request(head_only=True)

    def _handle_request(self, *, head_only: bool) -> None:
        started_at = time.time()
        status = HTTPStatus.INTERNAL_SERVER_ERROR
        cache_status = "miss"
        error_message = None

        try:
            status, cache_status = self._dispatch_request(head_only=head_only)
        except UpstreamNotFound:
            error_message = "Requested registry resource was not found."
            if urllib.parse.urlparse(self.path).path == "/readyz":
                status = HTTPStatus.SERVICE_UNAVAILABLE
                self._service_unavailable(error_message, head_only=head_only)
            else:
                status = HTTPStatus.NOT_FOUND
                self._not_found(error_message, head_only=head_only)
        except urllib.error.HTTPError as error:
            if error.code == HTTPStatus.NOT_FOUND:
                error_message = "Requested registry resource was not found."
                status = HTTPStatus.NOT_FOUND
                self._not_found(error_message, head_only=head_only)
            else:
                error_message = f"Upstream request failed with status {error.code}."
                status = HTTPStatus.BAD_GATEWAY
                self._bad_gateway(error_message, head_only=head_only)
        except UpstreamUnavailable as error:
            error_message = str(error)
            if urllib.parse.urlparse(self.path).path == "/readyz":
                status = HTTPStatus.SERVICE_UNAVAILABLE
                self._service_unavailable(error_message, head_only=head_only)
            else:
                status = HTTPStatus.BAD_GATEWAY
                self._bad_gateway(error_message, head_only=head_only)
        except Exception as error:  # noqa: BLE001
            error_message = str(error)
            status = HTTPStatus.BAD_GATEWAY
            self._bad_gateway(error_message, head_only=head_only)
        finally:
            duration_ms = int((time.time() - started_at) * 1000)
            print(
                json.dumps(
                    {
                        "event": "request",
                        "method": self.command,
                        "path": self.path,
                        "status": int(status),
                        "duration_ms": duration_ms,
                        "cache_status": cache_status,
                        "error": error_message,
                    },
                    sort_keys=True,
                )
            )

    def log_message(self, format: str, *args) -> None:
        return

    def _dispatch_request(self, *, head_only: bool) -> Tuple[HTTPStatus, str]:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/healthz":
            self._write_json(HTTPStatus.OK, {"status": "ok"}, head_only=head_only)
            return HTTPStatus.OK, "none"

        if path == "/readyz":
            readiness_cache_status = self._check_readiness()
            self._write_json(
                HTTPStatus.OK,
                {"status": "ok"},
                head_only=head_only,
                extra_headers={"X-Registry-Cache": readiness_cache_status},
            )
            return HTTPStatus.OK, readiness_cache_status

        if path == "/api/package-names":
            payload, cache_status = self._fetch_json(self.config.package_names_url())
            self._write_json(
                HTTPStatus.OK,
                payload,
                head_only=head_only,
                extra_headers={"X-Registry-Cache": cache_status},
            )
            return HTTPStatus.OK, cache_status

        if path.startswith("/api/packages/"):
            subpath = path.removeprefix("/api/packages/").strip("/")
            if not subpath:
                self._not_found("Package name is required.", head_only=head_only)
                return HTTPStatus.NOT_FOUND, "none"

            segments = subpath.split("/")
            if len(segments) == 1:
                package_name = segments[0]
                payload, cache_status = self._fetch_json(
                    self.config.metadata_url(package_name)
                )
                self._write_json(
                    HTTPStatus.OK,
                    payload,
                    content_type="application/vnd.pub.v2+json",
                    head_only=head_only,
                    extra_headers={"X-Registry-Cache": cache_status},
                )
                return HTTPStatus.OK, cache_status

            if len(segments) == 3 and segments[1] == "versions":
                package_name = segments[0]
                version = segments[2]
                metadata, cache_status = self._fetch_json(
                    self.config.metadata_url(package_name)
                )
                version_payload = self._find_version_payload(metadata, package_name, version)
                self._write_json(
                    HTTPStatus.OK,
                    version_payload,
                    content_type="application/vnd.pub.v2+json",
                    head_only=head_only,
                    extra_headers={"X-Registry-Cache": cache_status},
                )
                return HTTPStatus.OK, cache_status

            self._not_found(f"Unsupported path: {path}", head_only=head_only)
            return HTTPStatus.NOT_FOUND, "none"

        if (
            path.startswith("/packages/")
            and path.endswith(".tar.gz")
            and "/versions/" in path
        ):
            package_name, version = self._parse_archive_path(path)
            metadata, cache_status = self._fetch_json(
                self.config.metadata_url(package_name)
            )
            self._find_version_payload(metadata, package_name, version)
            self._redirect(
                self.config.archive_redirect_url(package_name, version),
                head_only=head_only,
                extra_headers={"X-Registry-Cache": cache_status},
            )
            return HTTPStatus.FOUND, cache_status

        self._not_found(f"Unsupported path: {path}", head_only=head_only)
        return HTTPStatus.NOT_FOUND, "none"

    def _check_readiness(self) -> str:
        payload, cache_status = self._fetch_json(
            self.config.package_names_url(),
            allow_stale_on_failure=False,
            prefer_cache=False,
        )
        packages = payload.get("packages")
        if not isinstance(packages, list):
            raise UpstreamUnavailable(
                "Upstream readiness check failed: package-names payload is invalid."
            )

        first_package = next(
            (package for package in packages if isinstance(package, str) and package),
            None,
        )
        if first_package is not None:
            try:
                self._fetch_json(
                    self.config.metadata_url(first_package),
                    allow_stale_on_failure=False,
                    prefer_cache=False,
                )
            except UpstreamNotFound as error:
                raise UpstreamUnavailable(
                    f"Upstream readiness check failed for package {first_package}."
                ) from error

        return cache_status

    def _fetch_json(
        self,
        url: str,
        *,
        allow_stale_on_failure: bool = True,
        prefer_cache: bool = True,
    ) -> Tuple[dict, str]:
        cache_key = hashlib.sha256(url.encode("utf-8")).hexdigest()

        if prefer_cache:
            cached, cache_status = self.cache.get(cache_key, allow_stale=False)
            if cached is not None:
                payload = json.loads(cached.decode("utf-8"))
                if not isinstance(payload, dict):
                    raise ValueError(f"Cached payload for {url} is not an object.")
                return payload, cache_status

        last_error: Optional[BaseException] = None
        attempts = self.config.upstream_retry_count + 1
        for attempt in range(attempts):
            request = urllib.request.Request(
                url,
                headers={"Accept": "application/json"},
                method="GET",
            )
            try:
                with urllib.request.urlopen(
                    request, timeout=self.config.upstream_timeout_seconds
                ) as response:
                    body = response.read()
                self.cache.put(cache_key, body)
                payload = json.loads(body.decode("utf-8"))
                if not isinstance(payload, dict):
                    raise ValueError(f"Payload for {url} is not a JSON object.")
                return payload, "upstream"
            except urllib.error.HTTPError as error:
                if error.code == HTTPStatus.NOT_FOUND:
                    raise UpstreamNotFound from error
                last_error = error
            except urllib.error.URLError as error:
                last_error = error

            if attempt < attempts - 1 and self.config.upstream_retry_backoff_seconds > 0:
                time.sleep(self.config.upstream_retry_backoff_seconds)

        if allow_stale_on_failure:
            cached, cache_status = self.cache.get(cache_key, allow_stale=True)
            if cached is not None:
                payload = json.loads(cached.decode("utf-8"))
                if not isinstance(payload, dict):
                    raise ValueError(f"Cached payload for {url} is not an object.")
                return payload, cache_status

        if last_error is not None:
            raise UpstreamUnavailable(
                f"Upstream request failed for {url}: {last_error}"
            ) from last_error
        raise UpstreamUnavailable(f"Upstream request failed for {url}.")

    def _find_version_payload(
        self, metadata: dict, package_name: str, version: str
    ) -> dict:
        versions = metadata.get("versions")
        if not isinstance(versions, list):
            raise UpstreamUnavailable(
                f"Package metadata for {package_name} is missing versions."
            )

        for entry in versions:
            if isinstance(entry, dict) and entry.get("version") == version:
                return entry

        raise UpstreamNotFound

    def _parse_archive_path(self, path: str) -> Tuple[str, str]:
        segments = path.strip("/").split("/")
        if len(segments) != 4 or segments[0] != "packages" or segments[2] != "versions":
            raise ValueError(f"Invalid archive path: {path}")
        package_name = segments[1]
        version = segments[3].removesuffix(".tar.gz")
        return package_name, version

    def _write_json(
        self,
        status: HTTPStatus,
        payload: dict,
        *,
        content_type: str = "application/json",
        head_only: bool,
        extra_headers: Optional[dict] = None,
    ) -> None:
        body = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=60")
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, str(value))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def _redirect(
        self,
        location: str,
        *,
        head_only: bool,
        extra_headers: Optional[dict] = None,
    ) -> None:
        self.send_response(HTTPStatus.FOUND)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "public, max-age=300")
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, str(value))
        self.end_headers()
        if not head_only:
            self.wfile.write(b"")

    def _not_found(self, message: str, *, head_only: bool) -> None:
        self._write_json(
            HTTPStatus.NOT_FOUND,
            {"error": {"code": "not_found", "message": message}},
            head_only=head_only,
        )

    def _bad_gateway(self, message: str, *, head_only: bool) -> None:
        self._write_json(
            HTTPStatus.BAD_GATEWAY,
            {"error": {"code": "bad_gateway", "message": message}},
            head_only=head_only,
        )

    def _service_unavailable(self, message: str, *, head_only: bool) -> None:
        self._write_json(
            HTTPStatus.SERVICE_UNAVAILABLE,
            {"error": {"code": "service_unavailable", "message": message}},
            head_only=head_only,
        )


def main() -> None:
    config = Config()
    cache = Cache(config.cache_dir, config.cache_ttl_seconds)
    RegistryGateway.config = config
    RegistryGateway.cache = cache

    server = ThreadingHTTPServer((config.host, config.port), RegistryGateway)
    print(
        json.dumps(
            {
                "event": "startup",
                "host": config.host,
                "port": config.port,
                "index_base_url": config.index_base_url,
                "cache_dir": str(config.cache_dir),
            },
            sort_keys=True,
        )
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
