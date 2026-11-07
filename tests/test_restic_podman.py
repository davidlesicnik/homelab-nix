from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "stage", Path(__file__).parents[1] / "scripts/restic-podman-stage.py"
)
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class PreflightTests(unittest.TestCase):
    def test_failed_nas_preflight_does_not_reach_staging(self):
        module = (Path(__file__).parents[1] / "modules/nixos/restic-podman.nix").read_text()
        hook = module.split("backupPrepareCommand = ''", 1)[1].split("'';", 1)[0]
        hook = hook.replace("${restic}", "fake_restic").replace("${staging}", "fake_stage")
        functions = '''
fake_restic() {
    if [ "$1" = cat ]; then return "$CAT_STATUS"; fi
    return "$INIT_STATUS"
}
fake_stage() { printf 'staged'; }
'''
        # Deliberately omit errexit, matching writeScript's execution environment.
        for cat_status, init_status, expected in ((1, 7, 7), (1, 0, 0), (0, 7, 0)):
            with self.subTest(cat=cat_status, init=init_status):
                result = subprocess.run(
                    ["bash", "-c", functions + hook], capture_output=True, text=True,
                    env={**os.environ, "CAT_STATUS": str(cat_status), "INIT_STATUS": str(init_status)},
                )
                self.assertEqual(result.returncode, expected)
                self.assertEqual(result.stdout, "staged" if expected == 0 else "")


class StagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        source = root / "database"
        source.mkdir()
        self.config = {
            "stage": str(root / "staging"),
            "state": str(root / "state"),
            "sources": [str(source)],
            "services": ["app.service", "db.service", "disabled.service"],
            "migrationMarkers": [],
            "copyTimeoutSeconds": 3600,
        }
        Path(self.config["state"]).mkdir()
        self.pending = Path(self.config["state"]) / "stopped-services.json"
        self.states = {"app.service": "active", "db.service": "active", "disabled.service": "inactive"}
        self.calls = []

    def command(self, *args, **kwargs):
        self.calls.append(args)
        if args[:2] == ("systemctl", "show"):
            return subprocess.CompletedProcess(args, 0, stdout=self.states[args[-1]] + "\n")
        if args[:2] == ("systemctl", "stop"):
            # The recovery record must exist before any unit is stopped.
            self.assertEqual(json.loads(self.pending.read_text()), ["app.service", "db.service"])
            self.states.update({unit: "inactive" for unit in args[2:]})
        if args[:2] == ("systemctl", "start"):
            self.states.update({unit: "active" for unit in args[2:]})
        online_copy = (args[0] == sys.executable or (
            args[0] == "rsync" and args[-2].rstrip("/") in self.config.get("onlineSqlite", {})
        ))
        if online_copy:
            self.assertEqual(self.states["app.service"], "active")
            self.assertEqual(self.states["db.service"], "active")
            self.assertFalse(self.pending.exists())
            self.assertFalse(any(call[:2] == ("systemctl", "stop") for call in self.calls))
        elif args[0] == "rsync":
            self.assertTrue(all(self.states[unit] == "inactive" for unit in self.config["services"]))
        return subprocess.CompletedProcess(args, 0)

    def online_database(self, locked=False):
        source = Path(self.temporary.name) / "authelia"
        source.mkdir()
        self.config["sources"].append(str(source))
        self.config["onlineSqlite"] = {str(source): "db.sqlite3"}
        self.states["authelia.service"] = "active"
        connection = sqlite3.connect(source / "db.sqlite3")
        self.addCleanup(connection.close)
        connection.execute("PRAGMA journal_mode=" + ("DELETE" if locked else "WAL"))
        connection.execute("CREATE TABLE registrations (name TEXT)")
        connection.execute("INSERT INTO registrations VALUES ('committed MFA')")
        connection.commit()
        if locked:
            connection.execute("BEGIN EXCLUSIVE")
        connection.execute("INSERT INTO registrations VALUES ('uncommitted')")
        return source

    def real_copy_command(self, *args, **kwargs):
        result = self.command(*args, **kwargs)
        if args[0] in ("rsync", sys.executable):
            return subprocess.run(args, check=True, **kwargs)
        return result

    @unittest.skipUnless(shutil.which("rsync"), "needs rsync")
    def test_online_backup_includes_committed_wal_without_stopping_authelia(self):
        source = self.online_database()
        (source / "notification.txt").write_text("notification fixture")
        database = source / "db.sqlite3"
        database.chmod(0o640)
        destination = Path(self.config["stage"]) / str(source).lstrip("/")
        destination.mkdir(parents=True)
        # Simulate journals retained from a previous cold backup.
        for suffix in ("-wal", "-shm", "-journal"):
            (destination / (database.name + suffix)).write_bytes(b"stale")
        with patch.object(stage, "run", side_effect=self.real_copy_command):
            stage.prepare(self.config)
        self.assertEqual(self.states["authelia.service"], "active")
        self.assertFalse(any("authelia.service" in call for call in self.calls))
        with closing(sqlite3.connect(destination / database.name)) as restored:
            self.assertEqual(restored.execute("PRAGMA quick_check").fetchall(), [("ok",)])
            self.assertEqual(restored.execute("SELECT * FROM registrations").fetchall(), [("committed MFA",)])
        for suffix in ("-wal", "-shm", "-journal", ".backup"):
            self.assertFalse((destination / (database.name + suffix)).exists())
        self.assertEqual((destination / database.name).stat().st_mode & 0o777, 0o640)
        self.assertEqual((destination / "notification.txt").read_text(), "notification fixture")

    def test_missing_online_database_fails_before_stopping_services(self):
        source = Path(self.config["sources"][0])
        self.config["onlineSqlite"] = {str(source): "missing.sqlite3"}
        with patch.object(stage, "run", side_effect=self.command):
            with self.assertRaisesRegex(RuntimeError, "Missing or unsafe SQLite"):
                stage.prepare(self.config)
        self.assertEqual(self.calls, [])
        self.assertFalse((source / "missing.sqlite3").exists())

    def test_online_database_failure_or_timeout_never_stops_cold_services(self):
        source = self.online_database()
        for failure in (subprocess.CalledProcessError(1, "sqlite"), subprocess.TimeoutExpired("sqlite", 3600)):
            with self.subTest(failure=type(failure).__name__):
                def command(*args, **kwargs):
                    result = self.command(*args, **kwargs)
                    if args[0] == sys.executable:
                        self.assertEqual(kwargs["timeout"], self.config["copyTimeoutSeconds"])
                        Path(args[-1] + ".backup").touch()
                        raise failure
                    return result
                with patch.object(stage, "run", side_effect=command):
                    with self.assertRaises(type(failure)):
                        stage.prepare(self.config)
                self.assertEqual(self.states["app.service"], "active")
                self.assertEqual(self.states["authelia.service"], "active")
                self.assertFalse(self.pending.exists())
                self.assertFalse((Path(self.config["stage"]) / "manifest.json").exists())
                destination = Path(self.config["stage"]) / str(source).lstrip("/")
                self.assertFalse((destination / "db.sqlite3.backup").exists())
                self.assertFalse(any(call[:2] == ("systemctl", "stop") for call in self.calls))

    @unittest.skipUnless(shutil.which("rsync"), "needs rsync")
    def test_real_locked_sqlite_times_out_without_stopping_other_services(self):
        source = self.online_database(locked=True)
        self.config["copyTimeoutSeconds"] = 1
        with patch.object(stage, "run", side_effect=self.real_copy_command):
            with self.assertRaises(subprocess.TimeoutExpired):
                stage.prepare(self.config)
        self.assertEqual(self.states["app.service"], "active")
        self.assertEqual(self.states["db.service"], "active")
        self.assertEqual(self.states["authelia.service"], "active")
        self.assertFalse(any(call[:2] == ("systemctl", "stop") for call in self.calls))
        self.assertFalse(self.pending.exists())
        self.assertFalse((Path(self.config["stage"]) / "manifest.json").exists())
        destination = Path(self.config["stage"]) / str(source).lstrip("/")
        self.assertFalse((destination / "db.sqlite3.backup").exists())

    def test_online_file_copy_failure_never_stops_cold_services(self):
        self.online_database()
        def command(*args, **kwargs):
            result = self.command(*args, **kwargs)
            if args[0] == "rsync":
                raise subprocess.CalledProcessError(23, "rsync")
            return result
        with patch.object(stage, "run", side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                stage.prepare(self.config)
        self.assertFalse(any(call[:2] == ("systemctl", "stop") for call in self.calls))
        self.assertFalse(self.pending.exists())
        self.assertFalse((Path(self.config["stage"]) / "manifest.json").exists())

    def test_recovery_failure_does_not_publish_manifest(self):
        def command(*args, **kwargs):
            if args[:2] == ("systemctl", "start"):
                raise subprocess.CalledProcessError(1, args)
            return self.command(*args, **kwargs)
        with patch.object(stage, "run", side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                stage.prepare(self.config)
        self.assertTrue(self.pending.exists())
        self.assertFalse((Path(self.config["stage"]) / "manifest.json").exists())

    def test_corrupt_sqlite_backup_preserves_previous_snapshot(self):
        root = Path(self.temporary.name)
        source = root / "corrupt.sqlite3"
        source.write_bytes(b"this is not a SQLite database")
        destination = root / "snapshot.sqlite3"
        destination.write_bytes(b"previous snapshot")
        with self.assertRaises(sqlite3.DatabaseError):
            stage.backup_sqlite(source, destination)
        self.assertEqual(destination.read_bytes(), b"previous snapshot")
        self.assertFalse((root / "snapshot.sqlite3.backup").exists())

    def test_cold_copy_resumes_only_previously_active_units(self):
        with patch.object(stage, "run", side_effect=self.command):
            stage.prepare(self.config)
        self.assertEqual(self.states["disabled.service"], "inactive")
        self.assertEqual(self.states["app.service"], "active")
        self.assertFalse(self.pending.exists())
        self.assertTrue((Path(self.config["stage"]) / "manifest.json").exists())

    def test_copy_uses_configured_timeout_and_service_commands_keep_short_timeout(self):
        self.config["copyTimeoutSeconds"] = 7200
        real_run = stage.run

        def command(args, **kwargs):
            self.assertEqual(kwargs["timeout"], 7200 if args[0] == "rsync" else 300)
            self.assertTrue(kwargs["check"])
            return self.command(*args, **kwargs)

        with patch.object(stage.subprocess, "run", side_effect=command):
            real_run("systemctl", "show", "--property=ActiveState", "--value", "app.service")
            stage.prepare(self.config)

    def test_copy_failure_and_timeout_resume_services_without_publishing_manifest(self):
        for failure in (subprocess.CalledProcessError(23, "rsync"), subprocess.TimeoutExpired("rsync", 3600)):
            with self.subTest(failure=type(failure).__name__):
                def command(*args, **kwargs):
                    if args[0] == "rsync":
                        raise failure
                    return self.command(*args, **kwargs)
                with patch.object(stage, "run", side_effect=command):
                    with self.assertRaises(type(failure)):
                        stage.prepare(self.config)
                self.assertEqual(self.states["db.service"], "active")
                self.assertFalse(self.pending.exists())
                self.assertFalse((Path(self.config["stage"]) / "manifest.json").exists())

    def test_partial_stop_failure_still_recovers_every_recorded_unit(self):
        def command(*args, **kwargs):
            result = self.command(*args, **kwargs)
            if args[:2] == ("systemctl", "stop"):
                raise subprocess.CalledProcessError(1, args)
            return result
        with patch.object(stage, "run", side_effect=command):
            with self.assertRaises(subprocess.CalledProcessError):
                stage.prepare(self.config)
        self.assertEqual(self.states["app.service"], "active")
        self.assertFalse(self.pending.exists())

    def test_restart_failure_preserves_record_for_exec_stop_post_retry(self):
        self.pending.write_text(json.dumps(["app.service", "db.service"]))
        with patch.object(stage, "run", side_effect=subprocess.CalledProcessError(1, "systemctl")):
            with self.assertRaises(subprocess.CalledProcessError):
                stage.recover(self.config)
        self.assertTrue(self.pending.exists())
        with patch.object(stage, "run", side_effect=self.command):
            stage.recover(self.config)
        self.assertFalse(self.pending.exists())

    def test_missing_source_fails_before_stopping_services(self):
        Path(self.config["sources"][0]).rmdir()
        with patch.object(stage, "run", side_effect=self.command):
            with self.assertRaisesRegex(RuntimeError, "Missing or unsafe"):
                stage.prepare(self.config)
        self.assertNotIn(("systemctl", "stop", "app.service", "db.service"), self.calls)

    def test_concurrent_start_aborts_copy_and_recovers(self):
        def command(*args, **kwargs):
            result = self.command(*args, **kwargs)
            if args[:2] == ("systemctl", "stop"):
                self.states["db.service"] = "active"
            return result
        with patch.object(stage, "run", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "running writer"):
                stage.prepare(self.config)
        self.assertFalse(any(call[0] == "rsync" for call in self.calls))
        self.assertEqual(self.states["app.service"], "active")

    @unittest.skipUnless(sys.platform == "linux" and shutil.which("rsync"), "needs Linux rsync")
    def test_real_copy_preserves_metadata_and_updates_same_size_same_mtime(self):
        source = Path(self.config["sources"][0])
        data = source / "database"
        data.write_bytes(b"before")
        data.chmod(0o640)
        os.setxattr(data, "user.backup-test", b"preserved")
        (source / "hardlink").hardlink_to(data)
        (source / "symlink").symlink_to("database")
        old = source / "deleted"
        old.write_text("stale")

        def command(*args, **kwargs):
            if args[0] == "rsync":
                return subprocess.run(args, check=True, **kwargs)
            return self.command(*args, **kwargs)

        with patch.object(stage, "run", side_effect=command):
            stage.prepare(self.config)
            original_time = data.stat().st_mtime_ns
            data.write_bytes(b"after!")
            os.utime(data, ns=(original_time, original_time))
            old.unlink()
            stage.prepare(self.config)
        destination = Path(self.config["stage"]) / str(source).lstrip("/")
        restored = destination / "database"
        self.assertEqual(restored.read_bytes(), b"after!")
        self.assertEqual(restored.stat().st_mode & 0o777, 0o640)
        self.assertEqual(os.getxattr(restored, "user.backup-test"), b"preserved")
        self.assertEqual(restored.stat().st_ino, (destination / "hardlink").stat().st_ino)
        self.assertEqual(os.readlink(destination / "symlink"), "database")
        self.assertFalse((destination / "deleted").exists())

    @unittest.skipUnless(sys.platform == "linux" and shutil.which("restic") and shutil.which("rsync"),
                         "needs Linux restic and rsync")
    def test_real_encrypted_backup_integrity_check_and_restore(self):
        source = Path(self.config["sources"][0])
        (source / "database").write_bytes(b"application recovery fixture")
        online_source = self.online_database()
        marker = source.parent / ".migration-complete"
        marker.touch()
        self.config["migrationMarkers"] = [str(marker)]

        with patch.object(stage, "run", side_effect=self.real_copy_command):
            stage.prepare(self.config)
        root = Path(self.temporary.name)
        environment = {**os.environ, "RESTIC_PASSWORD": "disposable-test-repository-password",
                       "RESTIC_CACHE_DIR": str(root / "cache")}
        def restic(*args):
            return subprocess.run(["restic", "--repo", str(root / "repository"), *args],
                                  env=environment, check=True, capture_output=True, text=True)
        restic("init")
        restic("backup", "--host=podman", "--tag=podman", self.config["stage"])
        restic("check", "--read-data")
        manifest = restic("dump", "--host", "podman", "--tag", "podman", "latest",
                          str(Path(self.config["stage"]) / "manifest.json")).stdout
        self.assertEqual(json.loads(manifest), self.config)
        restic("restore", "latest", "--target", str(root / "restore"), "--verify")
        recovered_stage = root / "restore" / self.config["stage"].lstrip("/")
        self.assertEqual((recovered_stage / str(source).lstrip("/") / "database").read_bytes(),
                         b"application recovery fixture")
        self.assertTrue((recovered_stage / str(marker).lstrip("/")).exists())
        self.assertEqual(json.loads((recovered_stage / "manifest.json").read_text()), self.config)
        with closing(sqlite3.connect(recovered_stage / str(online_source).lstrip("/") / "db.sqlite3")) as restored:
            self.assertEqual(restored.execute("SELECT * FROM registrations").fetchall(), [("committed MFA",)])
        self.assertEqual(self.states["authelia.service"], "active")


if __name__ == "__main__":
    unittest.main()
