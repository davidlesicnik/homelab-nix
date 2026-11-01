import copy
import importlib.util
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "caddy_build_required", Path(__file__).resolve().parents[1] / "scripts/caddy-build-required.py"
)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class CaddyBuildSelection(unittest.TestCase):
    def test_host_only_lock_updates_skip_caddy(self):
        before = {
            "root": "root",
            "nodes": {
                "root": {"inputs": {"caddy-nixpkgs": "caddy", "nixpkgs": "host"}},
                "caddy": {"locked": {"rev": "caddy-old"}},
                "host": {"locked": {"rev": "host-old"}},
            },
        }
        after = copy.deepcopy(before)
        after["nodes"]["host"]["locked"]["rev"] = "host-new"
        self.assertFalse(selector.requires_build(["flake.lock"], before, after))
        after["nodes"]["caddy"]["locked"]["rev"] = "caddy-new"
        self.assertTrue(selector.requires_build(["flake.lock"], before, after))

    def test_input_added_requires_build(self):
        self.assertTrue(selector.requires_build(["flake.lock"], {}, {}))

    def test_source_changes(self):
        for path in ("stacks/caddy/package.nix", "stacks/caddy/image.nix", "stacks/caddy/config.nix", "stacks/caddy/config/sites/test.caddy"):
            with self.subTest(path=path):
                self.assertTrue(selector.requires_build([path]))
        self.assertFalse(selector.requires_build(["stacks/litara/Dockerfile", "modules/nixos/common.nix"]))

    def test_ci_docs_and_host_changes_skip_build(self):
        for path in (
            ".github/workflows/caddy-checks.yml",
            ".github/workflows/caddy-updates.yml",
            "scripts/update-caddy.py",
            "scripts/caddy-build-required.py",
            "tests/test_caddy_build_required.py",
            "stacks/caddy/config/sites/README.md",
            "stacks/caddy/default.nix",
            "stacks/caddy/secrets.yaml",
            "modules/nixos/common.nix",
        ):
            with self.subTest(path=path):
                self.assertFalse(selector.requires_build([path]))

    def test_flake_changes_compare_caddy_derivations(self):
        # A valid empty archive is sufficient: evaluation is mocked here.
        import io
        import tarfile
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w"):
            pass
        for after, expected in ((("image", "config"), False),
                                (("new-image", "config"), True),
                                (("image", "new-config"), True)):
            with self.subTest(after=after), patch.object(
                selector.subprocess, "check_output", return_value=archive.getvalue()
            ), patch.object(selector, "caddy_derivations", side_effect=[("image", "config"), after]):
                self.assertEqual(selector.flake_affects_caddy("base"), expected)

    def test_flake_evaluation_failure_is_not_silently_skipped(self):
        import subprocess
        with patch.dict(selector.os.environ, {"BASE_SHA": "base", "EVENT_NAME": "pull_request"}), patch.object(
            selector.subprocess, "check_output", return_value="flake.nix\0"
        ), patch.object(selector, "flake_affects_caddy", side_effect=subprocess.CalledProcessError(1, "nix")):
            with self.assertRaises(subprocess.CalledProcessError):
                selector.main()


if __name__ == "__main__":
    unittest.main()
