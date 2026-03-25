#!/usr/bin/env python3
import argparse
import http.server
import json
import os
import pathlib
import socketserver
import sys
import tempfile
import threading
import urllib.error
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from registry.gateway import server as gateway_server


class _ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False


class _QuietStaticHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        return


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry-dir", required=True)
    parser.add_argument(
        "--select",
        choices=("stable", "prerelease"),
        required=True,
    )
    return parser.parse_args()


def _json_from_url(url: str) -> dict:
    with urllib.request.urlopen(url) as response:
        return json.load(response)


def _select_package(gateway_base: str, selection: str) -> tuple[str, str]:
    payload = _json_from_url(f"{gateway_base}/api/package-names")
    names = payload.get("packages", [])
    if not isinstance(names, list):
        raise RuntimeError("package-names payload is invalid")

    for name in names:
        if not isinstance(name, str):
            continue
        metadata = _json_from_url(f"{gateway_base}/api/packages/{name}")
        latest = metadata.get("latest", {})
        version = latest.get("version")
        if not isinstance(version, str):
            continue
        is_prerelease = "-" in version
        if selection == "stable" and not is_prerelease:
            return name, version
        if selection == "prerelease" and is_prerelease:
            return name, version

    raise RuntimeError(f"No {selection} package found in registry output")


def main() -> int:
    args = _parse_args()
    registry_dir = pathlib.Path(args.registry_dir).resolve()
    if not registry_dir.exists():
        raise RuntimeError(f"Registry directory does not exist: {registry_dir}")

    static_handler = lambda *handler_args, **handler_kwargs: _QuietStaticHandler(  # noqa: E731
        *handler_args,
        directory=str(registry_dir),
        **handler_kwargs,
    )
    static_server = _ReusableTCPServer(("127.0.0.1", 0), static_handler)
    static_thread = threading.Thread(target=static_server.serve_forever, daemon=True)
    static_thread.start()

    try:
        upstream_base = f"http://127.0.0.1:{static_server.server_address[1]}"
        cache_dir = tempfile.TemporaryDirectory(prefix="xs-registry-smoke-")
        try:
            os.environ["REGISTRY_INDEX_BASE_URL"] = upstream_base
            os.environ["CACHE_DIR"] = cache_dir.name
            os.environ["CACHE_TTL_SECONDS"] = "300"
            os.environ["UPSTREAM_TIMEOUT_SECONDS"] = "5"
            os.environ["UPSTREAM_RETRY_COUNT"] = "0"
            os.environ["UPSTREAM_RETRY_BACKOFF_SECONDS"] = "0"
            os.environ["GITHUB_REPOSITORY"] = "xsoulspace/dart_flutter_packages"

            config = gateway_server.Config()
            cache = gateway_server.Cache(config.cache_dir, config.cache_ttl_seconds)
            gateway_server.RegistryGateway.config = config
            gateway_server.RegistryGateway.cache = cache

            gateway = _ReusableTCPServer(("127.0.0.1", 0), gateway_server.RegistryGateway)
            gateway_thread = threading.Thread(target=gateway.serve_forever, daemon=True)
            gateway_thread.start()

            try:
                gateway_base = f"http://127.0.0.1:{gateway.server_address[1]}"

                health = _json_from_url(f"{gateway_base}/healthz")
                if health != {"status": "ok"}:
                    raise RuntimeError("healthz did not return ok")

                readiness = _json_from_url(f"{gateway_base}/readyz")
                if readiness != {"status": "ok"}:
                    raise RuntimeError("readyz did not return ok")

                package_name, version = _select_package(gateway_base, args.select)
                metadata = _json_from_url(f"{gateway_base}/api/packages/{package_name}")
                if metadata.get("name") != package_name:
                    raise RuntimeError("package metadata lookup returned the wrong package")

                version_payload = _json_from_url(
                    f"{gateway_base}/api/packages/{package_name}/versions/{version}"
                )
                if version_payload.get("version") != version:
                    raise RuntimeError("version endpoint returned the wrong version")

                head_request = urllib.request.Request(
                    f"{gateway_base}/packages/{package_name}/versions/{version}.tar.gz",
                    method="HEAD",
                )
                opener = urllib.request.build_opener(_NoRedirectHandler())
                try:
                    opener.open(head_request)
                except urllib.error.HTTPError as error:
                    if error.code != 302:
                        raise
                else:
                    raise RuntimeError("archive redirect did not return 302")
            finally:
                gateway.shutdown()
                gateway.server_close()
                gateway_thread.join(timeout=5)
        finally:
            cache_dir.cleanup()
    finally:
        static_server.shutdown()
        static_server.server_close()
        static_thread.join(timeout=5)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
