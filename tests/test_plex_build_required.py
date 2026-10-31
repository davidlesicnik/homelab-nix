import copy
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "plex_build_required", Path(__file__).resolve().parents[1] / "scripts/plex-build-required.py"
)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class PlexBuildSelection(unittest.TestCase):
    def test_other_hosts_stacks_and_docs_skip_plex(self):
        paths = [
            "hosts/podman/default.nix", "modules/nixos/podman.nix",
            "modules/nixos/containers.nix", "stacks/ha-tablet/Dockerfile",
            "stacks/caddy/config/Caddyfile", "README.md", "secrets.md",
            "hosts/plex/README.md", "tests/test_plex_update.py",
        ]
        self.assertFalse(selector.requires_build(paths))

    def test_plex_sources_and_shared_modules_build(self):
        for path in [
            "hosts/plex/default.nix", "hosts/plex/secrets.yaml",
            "hosts/plex/cache-public-key", "hosts/plex/package.nix",
            "modules/nixos/common.nix", "modules/nixos/secrets.nix",
            "modules/nixos/beszel-agent.nix", "modules/nixos/beszel-agent-package.nix",
            "scripts/update-plex-lxc.py", "scripts/plex-build-required.py",
            "flake.nix", ".github/workflows/plex-lxc.yml",
        ]:
            with self.subTest(path=path):
                self.assertTrue(selector.requires_build(["README.md", path]))

    def test_only_plex_dependency_lock_changes_build(self):
        before = {
            "root": "root",
            "nodes": {
                "root": {"inputs": {"nixpkgs": "host", "sops-nix": "secrets",
                                     "disko": "disk", "caddy-nixpkgs": "caddy"}},
                "host": {"locked": {"rev": "host-old"}},
                "secrets": {"locked": {"rev": "sops-old"},
                            "inputs": {"nixpkgs": ["nixpkgs"], "helper": "helper"}},
                "helper": {"locked": {"rev": "helper-old"}},
                "disk": {"locked": {"rev": "disk-old"}},
                "caddy": {"locked": {"rev": "caddy-old"}},
            },
        }
        for node, expected in [("host", True), ("secrets", True), ("helper", True),
                               ("disk", False), ("caddy", False)]:
            with self.subTest(node=node):
                after = copy.deepcopy(before)
                after["nodes"][node]["locked"]["rev"] = "new"
                self.assertEqual(selector.requires_build(["flake.lock"], before, after), expected)

    def test_unknown_lock_layout_builds_conservatively(self):
        self.assertTrue(selector.requires_build(["flake.lock"], {}, {}))


if __name__ == "__main__":
    unittest.main()
