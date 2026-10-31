#!/usr/bin/env python3
"""Install a signed NixOS closure published by this repository's main workflow."""

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

REPOSITORY = "https://github.com/davidlesicnik/homelab-nix"
PROFILE = "/nix/var/nix/profiles/system"
REVISION_FILE = pathlib.Path("/etc/plex-build-revision")
STATE = pathlib.Path("/var/lib/plex-update")
SYSTEM_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-nixos-system-[A-Za-z0-9.+_-]+")


def command(*args, timeout=900):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def remote_revision():
    revision = command("git", "ls-remote", "--exit-code", REPOSITORY + ".git",
                       "refs/heads/main", timeout=45).split()[0]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Invalid main revision")
    return revision


def manifest(revision):
    url = f"{REPOSITORY}/releases/download/plex-{revision}/update.json"
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None  # The runner has not published this revision yet.
        raise
    if (data.get("revision") != revision
            or not SYSTEM_PATH.fullmatch(data.get("system", ""))
            or not re.fullmatch(r"[0-9a-f]{64}", data.get("sha256", ""))):
        raise ValueError("Invalid update manifest")
    return data


def download_cache(revision, expected_hash, work):
    archive = work / "cache.tar"
    url = f"{REPOSITORY}/releases/download/plex-{revision}/cache.tar"
    with urllib.request.urlopen(url, timeout=120) as response, archive.open("wb") as output:
        shutil.copyfileobj(response, output)
    with archive.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != expected_hash:
            raise ValueError("Update archive checksum mismatch")
    cache = work / "cache"
    cache.mkdir()
    with tarfile.open(archive) as source:
        source.extractall(cache, filter="data")
    archive.unlink()
    return cache


def healthy():
    for _ in range(12):
        try:
            command("systemctl", "is-active", "--quiet", "plex", timeout=10)
            with urllib.request.urlopen("http://127.0.0.1:32400/identity", timeout=5) as response:
                if response.status == 200:
                    return True
        except (subprocess.SubprocessError, OSError):
            pass
        time.sleep(5)
    return False


def activate(system):
    previous = str(pathlib.Path(PROFILE).resolve(strict=True))
    command("nix-env", "--profile", PROFILE, "--set", system)
    try:
        command(system + "/bin/switch-to-configuration", "switch", timeout=600)
        if not healthy():
            raise RuntimeError("Plex failed its health check")
    except Exception:
        print("Update failed; restoring the previous system", flush=True)
        command("nix-env", "--profile", PROFILE, "--set", previous)
        command(previous + "/bin/switch-to-configuration", "switch", timeout=600)
        raise


def update():
    revision = remote_revision()
    if REVISION_FILE.read_text().strip() == revision:
        return
    failed = STATE / "failed-revision"
    if failed.exists() and failed.read_text().strip() == revision:
        print(f"Not retrying failed revision {revision}; waiting for a new commit", flush=True)
        return
    data = manifest(revision)
    if data is None:
        print(f"Waiting for GitHub Actions to publish {revision}", flush=True)
        return
    STATE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="download-", dir=STATE) as temporary:
        work = pathlib.Path(temporary)
        cache = download_cache(revision, data["sha256"], work)
        system = data["system"]
        # No evaluation or builds: Nix imports the closure and checks signatures.
        command("nix", "copy", "--from", cache.as_uri(),
                "--option", "require-sigs", "true",
                "--out-link", str(work / "candidate"), system)
        if (pathlib.Path(system) / "etc/plex-build-revision").read_text().strip() != revision:
            raise ValueError("Signed system does not match the requested revision")
        if remote_revision() != revision:
            print("Main advanced during download; waiting for the newer build", flush=True)
            return
        try:
            activate(system)
        except Exception:
            failed.write_text(revision + "\n")
            raise
        failed.unlink(missing_ok=True)
        print(f"Installed Plex system for {revision}", flush=True)


if __name__ == "__main__":
    update()
