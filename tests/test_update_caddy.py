import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "update_caddy", Path(__file__).resolve().parents[1] / "scripts/update-caddy.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class CaddyUpdates(unittest.TestCase):
    def test_stable_tags_are_sorted_numerically(self):
        self.assertEqual(
            updater.latest_stable(["v0.9.0", "v0.10.0", "v1.0.0-rc1", "main"]),
            "v0.10.0",
        )
        with self.assertRaises(RuntimeError):
            updater.latest_stable(["v1.0.0-rc1"])

    def test_hash_must_belong_to_the_expected_derivation(self):
        digest = "sha256-" + "b" * 43 + "="
        log = (
            "error: hash mismatch in fixed-output derivation '/nix/store/caddy-src.drv':\n"
            f"  specified: {updater.FAKE_HASH}\n  got: {digest}\n"
        )
        self.assertEqual(updater.source_hash(log, "/nix/store/caddy-src.drv"), digest)
        with self.assertRaises(RuntimeError):
            updater.source_hash(log, "/nix/store/unrelated.drv")
        with self.assertRaises(RuntimeError):
            updater.source_hash("network failure", "/nix/store/caddy-src.drv")

    def test_failure_restores_both_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / updater.PACKAGE
            package.parent.mkdir(parents=True)
            package.write_text('plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];\nhash = "old";')
            (root / updater.LOCK).write_text("original lock")
            original = package.read_bytes()

            def fake_run(args, **kwargs):
                if args[0] == "gh":
                    return subprocess.CompletedProcess(args, 0, stdout="v0.2.5\n")
                if "update" in args:
                    self.assertEqual(args[-1], "caddy-nixpkgs")
                    (root / updater.LOCK).write_text("changed lock")
                    return subprocess.CompletedProcess(args, 0)
                raise RuntimeError("simulated source evaluation failure")

            with patch.object(updater, "ROOT", root), patch.object(updater, "run", fake_run):
                with self.assertRaisesRegex(RuntimeError, "simulated"):
                    updater.main()
            self.assertEqual(package.read_bytes(), original)
            self.assertEqual((root / updater.LOCK).read_text(), "original lock")


if __name__ == "__main__":
    unittest.main()
