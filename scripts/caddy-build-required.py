#!/usr/bin/env python3
"""Select Caddy builds without treating host-only lock updates as Caddy changes."""

import json
import os
import subprocess


def caddy_input(lock):
    nodes = lock["nodes"]
    name = nodes[lock["root"]]["inputs"]["caddy-nixpkgs"]
    return nodes[name]


def requires_build(paths, before_lock=None, after_lock=None):
    for path in paths:
        if (
            path == "flake.nix"
            or path.startswith("stacks/caddy/")
            or path in {
                "scripts/update-caddy.py",
                "scripts/caddy-build-required.py",
                "tests/test_update_caddy.py",
                "tests/test_caddy_build_required.py",
            }
            or path.startswith(".github/workflows/caddy-")
        ):
            return True
    if "flake.lock" in paths:
        try:
            return caddy_input(before_lock) != caddy_input(after_lock)
        except (KeyError, TypeError):
            # Build conservatively when adding or changing the input structure.
            return True
    return False


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
    print(str(requires_build(paths, before, after)).lower())


if __name__ == "__main__":
    main()
