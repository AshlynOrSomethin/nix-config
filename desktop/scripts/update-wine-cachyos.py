#!/usr/bin/env python3
"""Update the pinned CachyOS Wine source to the latest regular tag."""

import argparse
import re
import subprocess
import sys
from pathlib import Path


TAG_PATTERN = re.compile(
    r"cachyos-(?P<version>[0-9]+(?:\.[0-9]+)+)-(?P<date>[0-9]{8})-"
    r"(?P<flavor>wine|proton(?:-native|-slr)?)"
)
INPUT_PATTERN = re.compile(
    r'(?m)^(?P<prefix>[ \t]*url[ \t]*=[ \t]*"github:CachyOS/wine-cachyos/)'
    r'(?P<tag>[^"]+)(?P<suffix>"[ \t]*;[ \t]*)$'
)
FLAVOR_ORDER = {"wine": 0, "proton-slr": 1, "proton-native": 2, "proton": 3}


def tag_key(tag):
    match = TAG_PATTERN.fullmatch(tag)
    if match is None:
        raise ValueError(f"Unsupported CachyOS Wine tag: {tag}")
    version = tuple(int(part) for part in match.group("version").split("."))
    return version, match.group("date"), FLAVOR_ORDER[match.group("flavor")]


def latest_tag(refs):
    tags = []
    for line in refs.splitlines():
        _, separator, ref = line.partition("\t")
        if separator and ref.startswith("refs/tags/"):
            tag = ref.removeprefix("refs/tags/")
            if TAG_PATTERN.fullmatch(tag):
                tags.append(tag)
    if not tags:
        raise ValueError("No regular CachyOS Wine or Proton tags were found")
    return max(tags, key=tag_key)


def update_flake(root, latest, check_only=False):
    flake = root / "flake.nix"
    original = flake.read_text(encoding="utf-8")
    matches = list(INPUT_PATTERN.finditer(original))
    if len(matches) != 1:
        raise ValueError("Expected exactly one pinned CachyOS Wine input in flake.nix")

    match = matches[0]
    current = match.group("tag")
    if tag_key(latest) < tag_key(current):
        raise ValueError(f"Refusing to replace newer pinned tag {current} with {latest}")

    print(f"Current CachyOS Wine tag: {current}")
    print(f"Latest CachyOS Wine tag:  {latest}")
    if check_only or latest == current:
        return

    updated = original[: match.start("tag")] + latest + original[match.end("tag") :]
    if flake.read_text(encoding="utf-8") != original:
        raise RuntimeError("flake.nix changed while checking tags; retry the update")
    flake.write_text(updated, encoding="utf-8")
    try:
        subprocess.run(["nix", "flake", "update", "wine-cachyos"], cwd=root, check=True)
    except (OSError, subprocess.CalledProcessError) as error:
        if flake.read_text(encoding="utf-8") == updated:
            flake.write_text(original, encoding="utf-8")
            raise RuntimeError("Lock update failed; flake.nix was restored") from error
        raise RuntimeError(
            "Lock update failed and flake.nix changed concurrently; reconcile it manually"
        ) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="show the latest tag without changing files"
    )
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]

    try:
        refs = subprocess.run(
            [
                "git",
                "ls-remote",
                "--tags",
                "--refs",
                "https://github.com/CachyOS/wine-cachyos.git",
            ],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
            timeout=60,
        ).stdout
        update_flake(root, latest_tag(refs), check_only=args.check)
    except (
        OSError,
        ValueError,
        RuntimeError,
        subprocess.CalledProcessError,
        subprocess.TimeoutExpired,
    ) as error:
        print(f"CachyOS Wine update failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
