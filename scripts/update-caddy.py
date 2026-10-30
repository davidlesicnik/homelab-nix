#!/usr/bin/env python3
"""Refresh Caddy's flake input, stable Cloudflare tag and vendored source hash."""

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = Path("stacks/caddy/package.nix")
LOCK = Path("flake.lock")
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def run(args, *, capture=False, check=True):
    return subprocess.run(
        args, cwd=ROOT, text=True, capture_output=capture, check=check
    )


def latest_stable(tags):
    versions = [tag for tag in tags if re.fullmatch(r"v\d+\.\d+\.\d+", tag)]
    if not versions:
        raise RuntimeError("Cloudflare has no stable version tags")
    return max(versions, key=lambda tag: tuple(map(int, tag[1:].split("."))))


def replace_one(pattern, replacement, source):
    updated, count = re.subn(pattern, lambda _: replacement, source)
    if count != 1:
        raise RuntimeError(f"Expected exactly one match for {pattern!r}; got {count}")
    return updated


def source_hash(log, derivation):
    # Accept only Nix's mismatch for the exact Caddy source derivation we built.
    pattern = (
        r"hash mismatch in fixed-output derivation ['\"]"
        + re.escape(derivation)
        + r"['\"]:\s+specified:\s+"
        + re.escape(FAKE_HASH)
        + r"\s+got:\s+(sha256-[A-Za-z0-9+/]{43}=)"
    )
    match = re.search(pattern, log)
    if not match:
        raise RuntimeError("Caddy source build failed without the expected hash mismatch")
    return match[1]


def main():
    originals = {path: (ROOT / path).read_bytes() for path in (PACKAGE, LOCK)}
    try:
        tags = run(
            ["gh", "api", "repos/caddy-dns/cloudflare/tags", "--paginate", "--jq", ".[].name"],
            capture=True,
        ).stdout.splitlines()
        version = latest_stable(tags)
        run(NIX + ["flake", "update", "caddy-nixpkgs"])
        source = originals[PACKAGE].decode()
        source = replace_one(
            r"github\.com/caddy-dns/cloudflare@v\d+\.\d+\.\d+",
            f"github.com/caddy-dns/cloudflare@{version}",
            source,
        )
        source = replace_one(r'hash = "[^"]+";', f'hash = "{FAKE_HASH}";', source)
        (ROOT / PACKAGE).write_text(source)
        target = "path:.#packages.x86_64-linux.caddy.src"
        drv = run(NIX + ["eval", "--raw", target + ".drvPath"], capture=True).stdout
        result = run(NIX + ["build", "--no-link", "--print-build-logs", target], capture=True, check=False)
        if result.returncode == 0:
            raise RuntimeError("The placeholder hash unexpectedly passed verification")
        try:
            digest = source_hash(result.stderr, drv)
        except RuntimeError:
            print(result.stderr, flush=True)
            raise
        (ROOT / PACKAGE).write_text(source.replace(FAKE_HASH, digest))
        # Verify the real hash before leaving any proposed changes behind.
        run(NIX + ["build", "--no-link", target])
        print(f"Cloudflare {version}; verified Caddy source hash {digest}", flush=True)
    except BaseException:
        for path, contents in originals.items():
            (ROOT / path).write_bytes(contents)
        raise


if __name__ == "__main__":
    main()
