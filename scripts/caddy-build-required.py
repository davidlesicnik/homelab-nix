#!/usr/bin/env python3
"""Select Caddy builds without treating host-only lock updates as Caddy changes."""

import io
import json
import tarfile
import tempfile
import os
import subprocess


def caddy_input(lock):
    nodes = lock["nodes"]
    name = nodes[lock["root"]]["inputs"]["caddy-nixpkgs"]
    return nodes[name]


def requires_build(paths, before_lock=None, after_lock=None):
    for path in paths:
        if not path.endswith(".md") and (
            path in {"stacks/caddy/package.nix", "stacks/caddy/image.nix", "stacks/caddy/config.nix"}
            or path.startswith("stacks/caddy/config/")
        ):
            return True
    if "flake.lock" in paths:
        try:
            return caddy_input(before_lock) != caddy_input(after_lock)
        except (KeyError, TypeError):
            # Build conservatively when adding or changing the input structure.
            return True
    return False


# Compare actual derivations for flake wiring changes rather than guessing from
# text: a Plex/dev-shell edit must not cause a Caddy build.
CADDY_TARGETS = ("packages.x86_64-linux.caddy-image", "checks.x86_64-linux.caddy-config")


def caddy_derivations(root):
    return tuple(
        subprocess.check_output(
            ["nix", "eval", "--raw", "--no-write-lock-file", f"path:{root}#{target}.drvPath"],
            text=True,
        )
        for target in CADDY_TARGETS
    )


def flake_affects_caddy(base):
    archive = subprocess.check_output(["git", "archive", "--format=tar", base])
    with tempfile.TemporaryDirectory(prefix="caddy-base-") as directory:
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            source.extractall(directory, filter="data")
        return caddy_derivations(directory) != caddy_derivations(os.getcwd())


def main():
    base = os.environ.get("BASE_SHA", "")
    if os.environ.get("EVENT_NAME") == "workflow_dispatch" or not base or set(base) == {"0"}:
        print("true")
        return
    paths = subprocess.check_output(
        ["git", "diff", "--name-only", "-z", base, "HEAD"], text=True
    ).split("\0")
    before = after = None
    if "flake.lock" in paths:
        before = json.loads(subprocess.check_output(["git", "show", f"{base}:flake.lock"]))
        with open("flake.lock") as source:
            after = json.load(source)
    build = requires_build(paths, before, after)
    if not build and "flake.nix" in paths:
        build = flake_affects_caddy(base)
    print(str(build).lower())


if __name__ == "__main__":
    main()
