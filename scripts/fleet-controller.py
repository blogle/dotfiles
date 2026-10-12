#!/usr/bin/env python3
"""Fail-closed fleet adapter; policy and mutation remain owned by SDLC."""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fleet" / "manifest.yaml"
SECURITY_FLOOR = ROOT / "fleet" / "security-floor.json"
REQUIRED_CREDENTIALS = (
    "SDLC_FLEET_APP_ID",
    "SDLC_FLEET_APP_PRIVATE_KEY",
    "SDLC_RELEASE_APP_ID",
    "SDLC_RELEASE_APP_PRIVATE_KEY",
)
ALLOWED_EVENTS = {"push", "schedule", "workflow_dispatch"}


def fail(message):
    print(f"fleet: {message}", file=sys.stderr)
    return 2


def load_manifest():
    # The file is JSON-compatible YAML so the workflow needs no parser install.
    with MANIFEST.open(encoding="utf-8") as stream:
        manifest = json.load(stream)
    if manifest.get("schema") != 1:
        raise ValueError("unsupported manifest schema")
    owner = manifest.get("owner", {})
    if owner != {"login": "blogle", "id": 4959802}:
        raise ValueError("immutable owner identity does not match blogle")
    repositories = manifest.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise ValueError("repositories must be a non-empty list")
    names = set()
    for repository in repositories:
        if not isinstance(repository, dict):
            raise ValueError("each repository must be an object")
        if not isinstance(repository.get("name"), str) or not isinstance(
            repository.get("id"), int
        ):
            raise ValueError("each repository needs an immutable name and ID")
        if repository["name"] in names:
            raise ValueError(f"duplicate repository: {repository['name']}")
        names.add(repository["name"])
        if not isinstance(repository.get("enabled"), bool):
            raise ValueError(f"{repository['name']}: enabled must be boolean")
        if repository.get("suspended", False) not in (True, False):
            raise ValueError(f"{repository['name']}: suspended must be boolean")
    return manifest


def load_security_floor():
    with SECURITY_FLOOR.open(encoding="utf-8") as stream:
        floor = json.load(stream)
    required = {
        "schema": 1,
        "protected_default_branch": True,
        "allow_force_push": False,
        "allow_deletions": False,
        "agent_bypass": False,
        "app_bypass": False,
        "human_bypass_actor_id": None,
    }
    if floor != required:
        raise ValueError("security floor is missing a fail-closed invariant")
    return floor


def protected_context():
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    ref = os.environ.get("GITHUB_REF", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    return (
        event in ALLOWED_EVENTS
        and ref == "refs/heads/master"
        and repository == "blogle/dotfiles"
        and os.environ.get("GITHUB_ACTIONS") == "true"
    )


def credentials_present():
    return all(os.environ.get(name) for name in REQUIRED_CREDENTIALS)


def sdlc_adapter(mode, manifest_path):
    """Call only the versioned public SDLC fleet interface, never consumer code."""
    sdlc = os.environ.get("SDLC_CLI", "sdlc")
    help_result = subprocess.run([sdlc, "--help"], capture_output=True, text=True)
    if help_result.returncode != 0:
        return {"state": "unknown", "reason": "SDLC CLI unavailable"}
    fleet_help = subprocess.run([sdlc, "fleet", "--help"], capture_output=True, text=True)
    if fleet_help.returncode != 0:
        return {
            "state": "unsupported",
            "reason": "installed SDLC CLI has no fleet interface; no mutation attempted",
        }
    command = [sdlc, "fleet", mode, "--manifest", str(manifest_path)]
    if mode == "reconcile":
        command.append("--apply")
    result = subprocess.run(command, text=True)
    return {"state": "success" if result.returncode == 0 else "unsafe", "exit": result.returncode}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "plan", "status", "reconcile"))
    args = parser.parse_args()
    try:
        manifest = load_manifest()
        load_security_floor()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return fail(str(error))

    if args.command == "validate":
        print("fleet: manifest valid; immutable identities present")
        return 0

    if args.command == "status":
        repositories = []
        for repository in manifest["repositories"]:
            state = "suspended" if repository.get("suspended", False) else (
                "disabled" if not repository["enabled"] else "unknown"
            )
            repositories.append({"name": repository["name"], "state": state})
        print(json.dumps({"manifest": "valid", "protected_context": protected_context(),
                          "credentials_present": credentials_present(),
                          "repositories": repositories}))
        return 0

    if args.command == "reconcile":
        if not protected_context():
            return fail("reconcile requires a protected master workflow context")
        if os.environ.get("SDLC_FLEET_APPLY") != "1":
            print("fleet: apply is disabled; safe no-op")
            return 0
        if not credentials_present():
            print("fleet: credentials absent; safe no-op")
            return 0
        result = sdlc_adapter("reconcile", MANIFEST)
        print(json.dumps(result))
        return 0 if result["state"] == "success" else 1

    result = sdlc_adapter("plan", MANIFEST)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
