import copy
import importlib.util
import unittest
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
        for path in ("flake.nix", "stacks/caddy/config/sites/test.caddy", "scripts/update-caddy.py"):
            with self.subTest(path=path):
                self.assertTrue(selector.requires_build([path]))
        self.assertFalse(selector.requires_build(["stacks/litara/Dockerfile", "modules/nixos/common.nix"]))


if __name__ == "__main__":
    unittest.main()
