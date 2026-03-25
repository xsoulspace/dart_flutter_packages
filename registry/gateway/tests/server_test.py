import http.server
import json
import os
import pathlib
import socketserver
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import warnings

REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from registry.gateway import server as gateway_server

warnings.simplefilter("ignore", ResourceWarning)


class _ReusableTCPServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    block_on_close = False


class _FixtureUpstreamHandler(http.server.BaseHTTPRequestHandler):
    routes = {}

    def do_GET(self):
        route = self.routes.get(self.path)
        if route is None:
            self.send_response(404)
            self.end_headers()
            return

        status, payload = route
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        body = json.dumps(payload).encode("utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


class RegistryGatewayServerTest(unittest.TestCase):
    def setUp(self):
        self._temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp_dir.cleanup)

        self.upstream_server = _ReusableTCPServer(("127.0.0.1", 0), _FixtureUpstreamHandler)
        self.upstream_thread = threading.Thread(
            target=self.upstream_server.serve_forever, daemon=True
        )
        self.upstream_thread.start()
        self.addCleanup(self._shutdown_server, self.upstream_server, self.upstream_thread)

        self.upstream_base = f"http://127.0.0.1:{self.upstream_server.server_address[1]}"
        _FixtureUpstreamHandler.routes = {
            "/api/package-names.json": (200, {"packages": ["demo_pkg"]}),
            "/api/packages/demo_pkg.json": (
                200,
                {
                    "name": "demo_pkg",
                    "latest": {
                        "version": "1.0.0",
                        "archive_url": "https://pub.example/packages/demo_pkg/versions/1.0.0.tar.gz",
                        "archive_sha256": "abc123",
                        "pubspec": {"name": "demo_pkg", "version": "1.0.0"},
                        "published": "2026-03-06T00:00:00Z",
                    },
                    "versions": [
                        {
                            "version": "1.0.0",
                            "archive_url": "https://pub.example/packages/demo_pkg/versions/1.0.0.tar.gz",
                            "archive_sha256": "abc123",
                            "pubspec": {"name": "demo_pkg", "version": "1.0.0"},
                            "published": "2026-03-06T00:00:00Z",
                        }
                    ],
                },
            ),
        }

    def _start_gateway(self, *, ttl_seconds=300):
        os.environ["REGISTRY_INDEX_BASE_URL"] = self.upstream_base
        os.environ["CACHE_DIR"] = self._temp_dir.name
        os.environ["CACHE_TTL_SECONDS"] = str(ttl_seconds)
        os.environ["GITHUB_REPOSITORY"] = "xsoulspace/dart_flutter_packages"
        os.environ["UPSTREAM_TIMEOUT_SECONDS"] = "2"
        os.environ["UPSTREAM_RETRY_COUNT"] = "0"
        os.environ["UPSTREAM_RETRY_BACKOFF_SECONDS"] = "0"

        config = gateway_server.Config()
        cache = gateway_server.Cache(config.cache_dir, config.cache_ttl_seconds)
        gateway_server.RegistryGateway.config = config
        gateway_server.RegistryGateway.cache = cache

        server = _ReusableTCPServer(("127.0.0.1", 0), gateway_server.RegistryGateway)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self._shutdown_server, server, thread)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def test_get_head_and_version_endpoints(self):
        gateway_base = self._start_gateway()

        with urllib.request.urlopen(f"{gateway_base}/api/package-names") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response), {"packages": ["demo_pkg"]})

        request = urllib.request.Request(
            f"{gateway_base}/api/package-names", method="HEAD"
        )
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["X-Registry-Cache"], "fresh")

        with urllib.request.urlopen(
            f"{gateway_base}/api/packages/demo_pkg/versions/1.0.0"
        ) as response:
            self.assertEqual(response.status, 200)
            body = json.load(response)
            self.assertEqual(body["version"], "1.0.0")

        archive_request = urllib.request.Request(
            f"{gateway_base}/packages/demo_pkg/versions/1.0.0.tar.gz",
            method="HEAD",
        )
        opener = urllib.request.build_opener(NoRedirectHandler())
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            opener.open(archive_request)
        self.assertEqual(ctx.exception.code, 302)
        self.assertIn("Location", ctx.exception.headers)
        ctx.exception.close()

    def test_stale_cache_is_served_when_upstream_fails(self):
        gateway_base = self._start_gateway(ttl_seconds=0)

        with urllib.request.urlopen(f"{gateway_base}/api/packages/demo_pkg") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response)["name"], "demo_pkg")

        _FixtureUpstreamHandler.routes["/api/packages/demo_pkg.json"] = (
            500,
            {"error": "boom"},
        )

        with urllib.request.urlopen(f"{gateway_base}/api/packages/demo_pkg") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["X-Registry-Cache"], "stale")
            self.assertEqual(json.load(response)["name"], "demo_pkg")

    def test_readyz_returns_503_when_upstream_is_unavailable(self):
        gateway_base = self._start_gateway()
        _FixtureUpstreamHandler.routes["/api/package-names.json"] = (
            500,
            {"error": "down"},
        )

        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(f"{gateway_base}/readyz")
        self.assertEqual(ctx.exception.code, 503)

    @staticmethod
    def _shutdown_server(server, thread):
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


if __name__ == "__main__":
    unittest.main()
