"""Exercise the actual Mail MCP Caddy site against a recording upstream."""

import http.client
import http.server
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest


CADDY = os.environ.get("CADDY_BIN") or shutil.which("caddy")
SITE = Path(__file__).resolve().parents[1] / "stacks/caddy/config/sites/your-mail-mcp.caddy"


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@unittest.skipUnless(CADDY, "requires Caddy; also runs in the Nix caddy-config check")
class MailMCPProxyTests(unittest.TestCase):
    def test_route_boundary(self):
        received = []

        class Upstream(http.server.BaseHTTPRequestHandler):
            def handle_request(self):
                received.append((self.command, self.path, self.headers.get("Authorization")))
                status = 401 if self.path == "/mcp" and not self.headers.get("Authorization") else 200
                self.send_response(status)
                if status == 401:
                    self.send_header("WWW-Authenticate", 'Bearer resource_metadata="https://example.org/metadata"')
                self.send_header("Content-Length", "0")
                self.end_headers()

            do_GET = do_HEAD = do_POST = do_DELETE = do_PUT = do_OPTIONS = handle_request

            def log_message(self, *_args):
                pass

        upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        port = free_port()
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "Caddyfile"
            config.write_text(
                "{\n admin off\n auto_https off\n}\n"
                + SITE.read_text()
                .replace("mail-mcp.lesicnik.eu", f"http://127.0.0.1:{port}")
                .replace("    import cert\n", "")
                .replace("your-mail-mcp:8080", f"127.0.0.1:{upstream.server_port}")
            )
            with (Path(directory) / "caddy.log").open("w+") as log:
                process = subprocess.Popen(
                    [CADDY, "run", "--config", str(config), "--adapter", "caddyfile"],
                    stdout=log, stderr=log, cwd=directory,
                )
                try:
                    for _ in range(100):
                        if process.poll() is not None:
                            log.seek(0)
                            self.fail(log.read())
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                break
                        except OSError:
                            time.sleep(0.05)
                    else:
                        self.fail("Caddy did not start")

                    def request(method, path, token=None):
                        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                        headers = {"Authorization": token} if token else {}
                        try:
                            connection.request(method, path, headers=headers)
                            response = connection.getresponse()
                            response.read()
                            return response.status, response.getheader("WWW-Authenticate")
                        finally:
                            connection.close()

                    self.assertEqual(request("POST", "/mcp")[0], 401)
                    self.assertIn("Bearer", request("GET", "/mcp")[1])
                    for method in ("GET", "POST", "DELETE"):
                        self.assertEqual(request(method, "/mcp", "Bearer test-token")[0], 200)
                        self.assertEqual(received[-1][2], "Bearer test-token")
                    for path in (
                        "/.well-known/oauth-authorization-server",
                        "/.well-known/oauth-protected-resource",
                        "/.well-known/oauth-protected-resource/mcp",
                    ):
                        for method in ("GET", "HEAD"):
                            self.assertEqual(request(method, path)[0], 200)
                    for method, path in (("GET", "/authorize"), ("POST", "/authorize"),
                                         ("POST", "/register"), ("POST", "/token")):
                        self.assertEqual(request(method, path)[0], 200)
                    for method, path in (
                        ("GET", "/"), ("GET", "/attachment/test/1?exp=123&sig=test"),
                        ("GET", "/mcp/"), ("POST", "/mcp/arbitrary"),
                        ("GET", "/future-admin"), ("GET", "/token"),
                        ("GET", "/register"), ("POST", "/.well-known/oauth-protected-resource"),
                        ("PUT", "/mcp"), ("OPTIONS", "/mcp"), ("DELETE", "/authorize"),
                    ):
                        count = len(received)
                        self.assertEqual(request(method, path, "Bearer test-token")[0], 404)
                        self.assertEqual(len(received), count, f"forwarded blocked route: {method} {path}")
                finally:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
