#!/usr/bin/env python3
"""Stage cold application copies and online SQLite snapshots before remote I/O."""

from contextlib import closing
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys


SQLITE_JOURNALS = ("-wal", "-shm", "-journal")
SQLITE_TEMPORARIES = tuple(".backup" + suffix for suffix in ("", *SQLITE_JOURNALS))


def run(*args, **kwargs):
    kwargs.setdefault("timeout", 300)
    return subprocess.run(args, check=True, **kwargs)


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)
    # Persist the rename before the first service is stopped.
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def recover(config):
    pending = Path(config["state"]) / "stopped-services.json"
    if not pending.exists():
        return
    services = json.loads(pending.read_text())
    if services:
        # One transaction preserves systemd's database/application ordering.
        # Keep the record if any restart fails so recovery can be retried.
        run("systemctl", "start", *services)
        for service in services:
            run("systemctl", "is-active", "--quiet", service)
    pending.unlink()


def backup_sqlite(source, destination):
    # Never create an empty source database if the identity store is missing.
    temporary = destination.with_name(destination.name + ".backup")
    try:
        for suffix in ("", *SQLITE_JOURNALS):
            temporary.with_name(temporary.name + suffix).unlink(missing_ok=True)
        with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)) as reader:
            with closing(sqlite3.connect(temporary)) as writer:
                reader.backup(writer, pages=256)
                # Keep the snapshot self-contained even when the source uses WAL.
                writer.execute("PRAGMA journal_mode=DELETE")
                if writer.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                    raise RuntimeError(f"SQLite backup failed integrity check: {source}")
        shutil.copystat(source, temporary)
        metadata = source.stat()
        os.chown(temporary, metadata.st_uid, metadata.st_gid)
        # An older cold copy may have left journals belonging to another DB.
        for suffix in SQLITE_JOURNALS:
            destination.with_name(destination.name + suffix).unlink(missing_ok=True)
        temporary.replace(destination)
    finally:
        for suffix in ("", *SQLITE_JOURNALS):
            temporary.with_name(temporary.name + suffix).unlink(missing_ok=True)


def copy_source(config, source):
    destination = Path(config["stage"]) / str(source).lstrip("/")
    destination.mkdir(parents=True, exist_ok=True)
    database = config.get("onlineSqlite", {}).get(str(source))
    exclusions = []
    if database:
        # SQLite copies committed WAL data itself. Raw database and
        # journal copies cannot form a consistent live snapshot.
        for suffix in ("", *SQLITE_JOURNALS, *SQLITE_TEMPORARIES):
            exclusions.extend(["--exclude", f"/{database}{suffix}"])
    run("rsync", "--archive", "--hard-links", "--acls", "--xattrs",
        "--numeric-ids", "--one-file-system", "--checksum", "--delete", *exclusions, "--",
        f"{source}/", f"{destination}/", timeout=config["copyTimeoutSeconds"])
    if database:
        try:
            # Use a subprocess so locked/busy databases have the same
            # hard timeout as other copies, including SQLite retries.
            run(sys.executable, __file__, "sqlite", str(source / database),
                str(destination / database), timeout=config["copyTimeoutSeconds"])
        finally:
            for suffix in SQLITE_TEMPORARIES:
                (destination / (database + suffix)).unlink(missing_ok=True)


def prepare(config):
    recover(config)
    stage = Path(config["stage"])
    stage.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(stage, 0o700)
    sources = [Path(source) for source in config["sources"]]
    for source in sources:
        if not source.is_dir() or source.is_symlink():
            raise RuntimeError(f"Missing or unsafe backup source: {source}")
    online = config.get("onlineSqlite", {})
    for source, database in online.items():
        if (source not in config["sources"] or database in ("", ".", "..")
                or Path(database).name != database):
            raise RuntimeError(f"Invalid online SQLite source: {source}/{database}")
        path = Path(source) / database
        if not path.is_file() or path.is_symlink():
            raise RuntimeError(f"Missing or unsafe SQLite database: {path}")

    # Keep the staging copy incremental, but discard paths removed from Nix.
    previous = stage / "manifest.json"
    if previous.exists():
        for old in json.loads(previous.read_text())["sources"]:
            if old not in config["sources"]:
                destination = stage / old.lstrip("/")
                # Only clean paths recorded inside this private staging tree.
                if not destination.resolve().is_relative_to(stage.resolve()):
                    raise RuntimeError(f"Unsafe stale staging path: {destination}")
                if destination.exists():
                    shutil.rmtree(destination)

    # Complete live copies before taking any applications offline. A locked
    # database must not extend the downtime of unrelated services.
    for source in sources:
        if str(source) in online:
            copy_source(config, source)

    active = []
    for service in config["services"]:
        status = run("systemctl", "show", "--property=ActiveState", "--value", service,
                     capture_output=True, text=True).stdout.strip()
        if status in ("activating", "deactivating", "reloading"):
            raise RuntimeError(f"Service is changing state; retry later: {service}")
        if status == "active":
            active.append(service)

    pending = Path(config["state"]) / "stopped-services.json"
    write_json(pending, active)
    cold_sources = [source for source in sources if str(source) not in online]
    print(f"Stopping {len(active)} services to stage {len(cold_sources)} cold data paths", flush=True)
    try:
        if active:
            run("systemctl", "stop", *active)
        # Refuse a copy if a service was concurrently started or stop failed.
        for service in config["services"]:
            status = run("systemctl", "show", "--property=ActiveState", "--value", service,
                         capture_output=True, text=True).stdout.strip()
            if status not in ("inactive", "failed"):
                raise RuntimeError(f"Backup source still has a running writer: {service}")

        for source in cold_sources:
            copy_source(config, source)
    finally:
        recover(config)
        print("Application services resumed; cold staging phase finished", flush=True)

    for marker in config["migrationMarkers"]:
        source = Path(marker)
        destination = stage / marker.lstrip("/")
        if source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        elif destination.exists():
            destination.unlink()
    # Publish only after both copy phases and service recovery succeed.
    write_json(stage / "manifest.json", config)


def main():
    if sys.argv[1] == "sqlite":
        backup_sqlite(Path(sys.argv[2]), Path(sys.argv[3]))
        return
    config = json.loads(Path(sys.argv[1]).read_text())
    {"prepare": prepare, "recover": recover}[sys.argv[2]](config)


if __name__ == "__main__":
    main()
