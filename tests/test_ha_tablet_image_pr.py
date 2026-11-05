import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "image_pr", Path(__file__).resolve().parents[1] / "scripts/check-ha-tablet-image-pr.py"
)
image_pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image_pr)


class ImagePRTest(unittest.TestCase):
    def test_exact_image_only(self):
        image_pr.validate("codex/deploy-ha-tablet-" + "a" * 40,
                          ["stacks/ha-tablet/Dockerfile"],
                          "FROM git.lesicnik.eu/david/ha-tablet:" + "a" * 40 + "@sha256:" + "b" * 64 + "\n")

    def test_reject_extra_changes_wrong_commit_or_mutable_tag(self):
        branch = "codex/deploy-ha-tablet-" + "a" * 40
        path = ["stacks/ha-tablet/Dockerfile"]
        manifest = "FROM git.lesicnik.eu/david/ha-tablet:" + "a" * 40 + "@sha256:" + "b" * 64 + "\n"
        for args in [(branch, path + ["flake.nix"], manifest),
                     (branch, path, manifest.replace("a" * 40, "c" * 40)),
                     (branch, path, "FROM git.lesicnik.eu/david/ha-tablet:latest\n"),
                     ("main", path, manifest)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                image_pr.validate(*args)
