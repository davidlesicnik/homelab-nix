import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    "plex_update", pathlib.Path(__file__).parents[1] / "scripts/update-plex-lxc.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
REVISION = "a" * 40
SYSTEM = "/nix/store/" + "b" * 32 + "-nixos-system-plex-26.05"


class PlexUpdateTests(unittest.TestCase):
    def test_updater_follows_only_the_published_plex_tag(self):
        with patch.object(updater, "command", return_value=REVISION + "\trefs/tags/plex-current") as command:
            self.assertEqual(updater.published_revision(), REVISION)
            self.assertEqual(command.call_args.args[-1], "refs/tags/plex-current")

    def test_invalid_published_revision_is_rejected(self):
        with patch.object(updater, "command", return_value="invalid\trefs/tags/plex-current"):
            with self.assertRaises(ValueError):
                updater.published_revision()

    def test_missing_release_waits_without_activation(self):
        error = urllib.error.HTTPError("url", 404, "missing", {}, None)
        with patch.object(updater.urllib.request, "urlopen", side_effect=error):
            self.assertIsNone(updater.manifest(REVISION))

    def test_network_error_is_not_treated_as_pending_build(self):
        error = urllib.error.HTTPError("url", 500, "failure", {}, None)
        with patch.object(updater.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(urllib.error.HTTPError):
                updater.manifest(REVISION)

    def test_manifest_rejects_mismatched_commit_and_unsafe_paths(self):
        for revision, system in [("c" * 40, SYSTEM), (REVISION, "/tmp/payload")]:
            response = MagicMock()
            response.__enter__.return_value = io.BytesIO(json.dumps({
                "revision": revision, "system": system, "sha256": "d" * 64,
            }).encode())
            with patch.object(updater.urllib.request, "urlopen", return_value=response):
                with self.assertRaises(ValueError):
                    updater.manifest(REVISION)

    def test_corrupt_archive_is_rejected_before_extraction(self):
        response = MagicMock()
        response.__enter__.return_value = io.BytesIO(b"corrupt archive")
        with tempfile.TemporaryDirectory() as work:
            with patch.object(updater.urllib.request, "urlopen", return_value=response):
                with patch.object(updater.tarfile, "open") as extract:
                    with self.assertRaisesRegex(ValueError, "checksum"):
                        updater.download_cache(REVISION, "d" * 64, pathlib.Path(work))
                    extract.assert_not_called()

    def test_failed_signature_import_never_activates(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            revision_file = root / "revision"
            revision_file.write_text("old")
            with patch.object(updater, "STATE", root), \
                 patch.object(updater, "REVISION_FILE", revision_file), \
                 patch.object(updater, "published_revision", return_value=REVISION), \
                 patch.object(updater, "manifest", return_value={"system": SYSTEM, "sha256": "d" * 64}), \
                 patch.object(updater, "download_cache", return_value=root), \
                 patch.object(updater, "command", side_effect=subprocess.CalledProcessError(1, "nix copy")) as command, \
                 patch.object(updater, "activate") as activate:
                with self.assertRaises(subprocess.CalledProcessError):
                    updater.update()
                self.assertIn("require-sigs", command.call_args.args)
                self.assertIn("true", command.call_args.args)
                activate.assert_not_called()

    def test_new_published_build_during_download_does_not_install_old_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            revision_file = root / "revision"
            revision_file.write_text("old")
            system = root / "system"
            (system / "etc").mkdir(parents=True)
            (system / "etc/plex-build-revision").write_text(REVISION)
            with patch.object(updater, "STATE", root), \
                 patch.object(updater, "REVISION_FILE", revision_file), \
                 patch.object(updater, "published_revision", side_effect=[REVISION, "e" * 40]), \
                 patch.object(updater, "manifest", return_value={"system": str(system), "sha256": "d" * 64}), \
                 patch.object(updater, "download_cache", return_value=root), \
                 patch.object(updater, "command"), \
                 patch.object(updater, "activate") as activate:
                updater.update()
                activate.assert_not_called()

    def test_unhealthy_plex_restores_previous_profile_and_system(self):
        with tempfile.TemporaryDirectory() as previous:
            resolved = str(pathlib.Path(previous).resolve())
            with patch.object(updater, "PROFILE", previous), \
                 patch.object(updater, "command") as command, \
                 patch.object(updater, "healthy", return_value=False):
                with self.assertRaisesRegex(RuntimeError, "health check"):
                    updater.activate(SYSTEM)
                self.assertEqual(command.call_args_list[-2].args,
                                 ("nix-env", "--profile", previous, "--set", resolved))
                self.assertEqual(command.call_args_list[-1].args,
                                 (resolved + "/bin/switch-to-configuration", "switch"))

    def test_current_revision_needs_no_download_or_activation(self):
        with tempfile.TemporaryDirectory() as directory:
            revision_file = pathlib.Path(directory) / "revision"
            revision_file.write_text(REVISION)
            with patch.object(updater, "REVISION_FILE", revision_file), \
                 patch.object(updater, "published_revision", return_value=REVISION), \
                 patch.object(updater, "manifest") as manifest, \
                 patch.object(updater, "activate") as activate:
                updater.update()
                manifest.assert_not_called()
                activate.assert_not_called()

    def test_failed_revision_is_not_retried_every_two_minutes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            revision_file = root / "revision"
            revision_file.write_text("old")
            (root / "failed-revision").write_text(REVISION)
            with patch.object(updater, "STATE", root), \
                 patch.object(updater, "REVISION_FILE", revision_file), \
                 patch.object(updater, "published_revision", return_value=REVISION), \
                 patch.object(updater, "manifest") as manifest:
                updater.update()
                manifest.assert_not_called()

    def test_healthy_update_keeps_new_profile(self):
        with tempfile.TemporaryDirectory() as previous:
            with patch.object(updater, "PROFILE", previous), \
                 patch.object(updater, "command") as command, \
                 patch.object(updater, "healthy", return_value=True):
                updater.activate(SYSTEM)
                self.assertEqual(command.call_count, 2)
                self.assertEqual(command.call_args_list[0].args,
                                 ("nix-env", "--profile", previous, "--set", SYSTEM))


if __name__ == "__main__":
    unittest.main()
