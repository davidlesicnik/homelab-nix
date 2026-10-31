#!/usr/bin/env python3
"""Select Plex builds without rebuilding for other hosts, stacks or docs."""

import fnmatch
import json
import os
import subprocess


def plex_inputs(lock):
    nodes = lock["nodes"]
    inputs = nodes[lock["root"]]["inputs"]

    def resolve(reference):
        if isinstance(reference, str):
            return reference
        current = lock["root"]
        for name in reference:
            current = resolve(nodes[current]["inputs"][name])
        return current

    def graph(reference, ancestors=()):
        name = resolve(reference)
        if name in ancestors:
            raise ValueError("Cyclic flake inputs")
        node = nodes[name]
        return {
            **{key: value for key, value in node.items() if key != "inputs"},
            "inputs": {key: graph(value, (*ancestors, name))
                       for key, value in node.get("inputs", {}).items()},
        }

    return {name: graph(inputs[name]) for name in ("nixpkgs", "sops-nix")}


def requires_build(paths, before_lock=None, after_lock=None):
    for path in paths:
        if path.endswith(".md"):
            continue
        if (
            path.startswith("hosts/plex/")
            or path in {
                "flake.nix",
                "modules/nixos/common.nix",
                "modules/nixos/secrets.nix",
                "scripts/update-plex-lxc.py",
                "scripts/plex-build-required.py",
                ".github/workflows/plex-lxc.yml",
            }
            or fnmatch.fnmatchcase(path, "modules/nixos/beszel-agent*.nix")
        ):
            return True
    if "flake.lock" in paths:
        try:
            return plex_inputs(before_lock) != plex_inputs(after_lock)
        except (KeyError, TypeError, ValueError, RecursionError):
            return True  # Build conservatively if the dependency layout changes.
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
