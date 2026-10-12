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
CONTROLLER = ROOT / "fleet" / "controller.json"
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
    }
    if any(floor.get(key) != value for key, value in required.items()):
        raise ValueError("security floor is missing a fail-closed invariant")
    bypass_id = floor.get("human_bypass_actor_id")
    if bypass_id is not None and (not isinstance(bypass_id, int) or bypass_id <= 0):
        raise ValueError("human bypass actor must be one positive GitHub user ID")
    return floor


def load_controller():
    with CONTROLLER.open(encoding="utf-8") as stream:
        controller = json.load(stream)
    if controller != {
        "schema": 1,
        "source": "github:blogle/sdlc",
        "revision": "517216b32898ce5bcb43091fdc547169c767075e",
        "derivation": "packages.x86_64-linux.sdlc",
        "interface": "fleet-v1",
        "policy_flag": "--policy",
        "trusted_bypass_flag": "--trusted-bypass-user-id",
    }:
        raise ValueError("trusted controller pin is invalid")
    return controller


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


class GitHubAPI:
    """Small injectable read client; no write-capable endpoint is exposed."""

    def get(self, path):
        result = subprocess.run(
            ["gh", "api", path], capture_output=True, text=True, check=True
        )
        return json.loads(result.stdout)


def verify_live_identities(manifest, api):
    owner = manifest["owner"]
    live_owner = api.get(f"users/{owner['login']}")
    if live_owner.get("login") != owner["login"] or live_owner.get("id") != owner["id"]:
        raise ValueError("live owner identity does not match immutable manifest identity")
    for repository in manifest["repositories"]:
        live = api.get(f"repos/{owner['login']}/{repository['name']}")
        if (
            live.get("id") != repository["id"]
            or live.get("name") != repository["name"]
            or live.get("owner", {}).get("id") != owner["id"]
        ):
            raise ValueError(f"live identity mismatch for {repository['name']}")
    return True


def repository_plan(repository):
    identity_key = f"{repository['name']}:{repository['id']}"
    if repository.get("suspended", False):
        return {"name": repository["name"], "idempotency_key": identity_key,
                "state": "suspended", "actions": []}
    if not repository["enabled"]:
        return {
            "name": repository["name"],
            "idempotency_key": identity_key,
            "state": "disabled",
            "actions": ["retain-protection", "retain-secrets", "disable-release-activation"],
        }
    return {
        "name": repository["name"],
        "idempotency_key": identity_key,
        "state": "unknown",
        "actions": [
            "verify-installation-and-policy",
            "verify-release-app-distribution",
            "verify-check-readiness",
            "enable-release-activation-last",
        ],
    }


def prepare_release_app_distribution(repository, api):
    """Prepare metadata only; secret values never cross this adapter."""
    owner = "blogle"
    current = api.get(f"repos/{owner}/{repository['name']}/actions/secrets")
    names = sorted(item.get("name", "") for item in current.get("secrets", []))
    return {
        "name": repository["name"],
        "operation": "upsert-protected-release-environment-secrets",
        "required_names": ["SDLC_RELEASE_APP_ID", "SDLC_RELEASE_APP_PRIVATE_KEY"],
        "existing_names": names,
        "write": False,
    }


def reconcile_repository(repository, worker):
    """Normalize one worker result without allowing one repo to affect another."""
    plan = repository_plan(repository)
    if plan["state"] in ("suspended", "disabled"):
        return plan
    try:
        result = worker(repository)
    except Exception as error:  # worker failures are transient/unknown, not unsafe
        return {"name": repository["name"], "state": "unknown", "reason": str(error)}
    if result.get("state") == "unsafe":
        return {"name": repository["name"], "state": "unsafe", "activation": "disabled"}
    if result.get("state") == "success":
        return {"name": repository["name"], "state": "ready", "activation": "enabled-last"}
    return {"name": repository["name"], "state": "unknown", "activation": "retain"}


def sdlc_adapter(mode, manifest_path, floor):
    """Invoke only the pinned worker contract; consumer code is never loaded."""
    controller = load_controller()
    bypass_id = floor.get("human_bypass_actor_id")
    if not bypass_id:
        return {"state": "unknown", "reason": "human bypass ID is not configured"}
    sdlc = os.environ.get("SDLC_CLI")
    if not sdlc or not Path(sdlc).is_file():
        return {"state": "unknown", "reason": "pinned SDLC CLI executable is unavailable"}
    command = [
        sdlc,
        "fleet",
        mode,
        controller["policy_flag"],
        str(manifest_path),
        controller["trusted_bypass_flag"],
        str(bypass_id),
    ]
    result = subprocess.run(command, text=True)
    return {"state": "success" if result.returncode == 0 else "unsafe", "exit": result.returncode}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("validate", "plan", "status", "reconcile"))
    args = parser.parse_args()
    try:
        manifest = load_manifest()
        floor = load_security_floor()
        load_controller()
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
                          "human_bypass_configured": bool(floor.get("human_bypass_actor_id")),
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
        try:
            verify_live_identities(manifest, GitHubAPI())
        except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
            return fail(f"live identity preflight failed: {error}")
        result = sdlc_adapter("reconcile", MANIFEST, floor)
        print(json.dumps(result))
        return 0 if result["state"] == "success" else 1

    result = {"state": "prepare-only", "repositories": [repository_plan(item) for item in manifest["repositories"]]}
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
