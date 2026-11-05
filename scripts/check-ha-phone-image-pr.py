#!/usr/bin/env python3
"""Constrain the image publisher's PR checks to one matching image declaration."""
import os
from pathlib import Path
import re
import subprocess


def validate(branch, paths, manifest):
    match = re.fullmatch(r"codex/deploy-ha-phone-([0-9a-f]{40})", branch)
    if not match or paths != ["stacks/ha-phone/Dockerfile"]:
        raise ValueError("Expected one HA Phone image declaration on its deployment branch")
    if not re.fullmatch(
        rf"FROM git\.lesicnik\.eu/david/ha-phone:{match[1]}@sha256:[0-9a-f]{{64}}\n", manifest
    ):
        raise ValueError("Image must match the source commit and include its digest")


if __name__ == "__main__":
    paths = subprocess.check_output(
        ["git", "diff", "--name-only", "origin/main...HEAD"], text=True
    ).splitlines()
    validate(os.environ["IMAGE_BRANCH"], paths, Path("stacks/ha-phone/Dockerfile").read_text())
