#!/usr/bin/env python3
"""Validate the small owner-pinned inventory used by the fleet workflow."""

import argparse
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fleet" / "manifest.yaml"
OWNER = {"login": "blogle", "id": 4959802}


def load_manifest():
    with MANIFEST.open(encoding="utf-8") as stream:
        manifest = json.load(stream)
    if manifest.get("schema") != 1 or manifest.get("owner") != OWNER:
        raise ValueError("fleet manifest must identify owner blogle (4959802)")
    repositories = manifest.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ValueError("fleet manifest has no repositories")
    names = set()
    for repository in repositories:
        if not isinstance(repository, dict):
            raise ValueError("fleet repository entries must be objects")
        name = repository.get("name")
        if not isinstance(name, str) or name in names:
            raise ValueError(f"invalid or duplicate repository: {name!r}")
        if not isinstance(repository.get("id"), int):
            raise ValueError(f"{name}: immutable GitHub ID is required")
        if not isinstance(repository.get("enabled"), bool):
            raise ValueError(f"{name}: enabled must be boolean")
        names.add(name)
    return manifest


def enabled_repositories(manifest):
    return [item for item in manifest["repositories"] if item["enabled"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "plan", "status"))
    args = parser.parse_args()
    try:
        manifest = load_manifest()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"fleet: {error}", file=sys.stderr)
        return 2

    if args.command == "validate":
        print("fleet: manifest valid")
        return 0
    repositories = [
        {"name": item["name"], "id": item["id"], "enabled": item["enabled"]}
        for item in manifest["repositories"]
    ]
    if args.command == "status":
        print(json.dumps({"owner": OWNER, "repositories": repositories}, sort_keys=True))
    else:
        print(json.dumps({"owner": OWNER, "enabled": enabled_repositories(manifest)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
