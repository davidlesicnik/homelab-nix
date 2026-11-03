#!/usr/bin/env python3
"""Make a cold copy of application data, resuming services before remote I/O."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


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


def prepare(config):
    recover(config)
    stage = Path(config["stage"])
    stage.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(stage, 0o700)
    sources = [Path(source) for source in config["sources"]]
    for source in sources:
        if not source.is_dir() or source.is_symlink():
            raise RuntimeError(f"Missing or unsafe backup source: {source}")

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
    print(f"Stopping {len(active)} services to stage {len(sources)} data paths", flush=True)
    try:
        if active:
            run("systemctl", "stop", *active)
        # Refuse a copy if a service was concurrently started or stop failed.
        for service in config["services"]:
            status = run("systemctl", "show", "--property=ActiveState", "--value", service,
                         capture_output=True, text=True).stdout.strip()
            if status not in ("inactive", "failed"):
                raise RuntimeError(f"Backup source still has a running writer: {service}")

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

        for source in sources:
            destination = stage / str(source).lstrip("/")
            destination.mkdir(parents=True, exist_ok=True)
            run("rsync", "--archive", "--hard-links", "--acls", "--xattrs",
                "--numeric-ids", "--one-file-system", "--checksum", "--delete", "--",
                f"{source}/", f"{destination}/")

        for marker in config["migrationMarkers"]:
            source = Path(marker)
            destination = stage / marker.lstrip("/")
            if source.is_file():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
            elif destination.exists():
                destination.unlink()
        write_json(stage / "manifest.json", config)
    finally:
        recover(config)
        print("Application services resumed; local staging phase finished", flush=True)


def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    {"prepare": prepare, "recover": recover}[sys.argv[2]](config)


if __name__ == "__main__":
    main()
