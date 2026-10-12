#!/usr/bin/env python3
"""Fail-closed fleet adapter; policy and mutation remain owned by SDLC."""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fleet" / "manifest.yaml"
SECURITY_FLOOR = ROOT / "fleet" / "security-floor.json"
CONTROLLER = ROOT / "fleet" / "controller.json"
POLICY = ROOT / "fleet" / "policy.json"
RELEASE_CREDENTIALS = ROOT / "fleet" / "release-credentials.json"
REQUIRED_CREDENTIALS = (
    "SDLC_FLEET_APP_ID",
    "SDLC_FLEET_APP_PRIVATE_KEY",
    "SDLC_RELEASE_APP_ID",
    "SDLC_RELEASE_APP_PRIVATE_KEY",
)
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
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
        if repository.get("state", "active") not in ("active", "suspended"):
            raise ValueError(f"{repository['name']}: state must be active or suspended")
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
        "revision": "c91e13d80ec8b3fd60690fd555006d34e8d9978b",
        "derivation": "packages.x86_64-linux.sdlc",
        "interface": "fleet-v1",
        "policy_flag": "--policy",
        "trusted_bypass_flag": "--trusted-bypass-user-id",
    }:
        raise ValueError("trusted controller pin is invalid")
    return controller


def verify_controller_pin(api):
    """Return an attestation only after the pin is ancestor of protected main."""
    controller = load_controller()
    source = api.get("repos/blogle/sdlc")
    commit = api.get(f"repos/blogle/sdlc/commits/{controller['revision']}")
    if source.get("id") != 1402311485 or source.get("default_branch") != "main":
        raise ValueError("trusted SDLC source identity or branch is unexpected")
    if commit.get("sha") != controller["revision"]:
        raise ValueError("trusted SDLC revision is unavailable")
    compare = api.get(
        f"repos/blogle/sdlc/compare/{controller['revision']}...{source['default_branch']}"
    )
    if compare.get("status") not in ("ahead", "identical") or compare.get("behind_by") != 0:
        raise ValueError(
            "trusted SDLC revision is not an ancestor of protected main; "
            "repin to a protected-main SDLC release after the controller revision lands"
        )
    return {
        "source": "blogle/sdlc",
        "repository_id": source["id"],
        "commit_sha": controller["revision"],
        "reachable_from_protected": True,
        "immutable": True,
        "verified_by": "dotfiles-trusted-controller",
    }


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
    observed = {}
    for repository in manifest["repositories"]:
        live = api.get(f"repos/{owner['login']}/{repository['name']}")
        if (
            live.get("id") != repository["id"]
            or live.get("name") != repository["name"]
            or live.get("owner", {}).get("id") != owner["id"]
        ):
            raise ValueError(f"live identity mismatch for {repository['name']}")
        if not live.get("default_branch"):
            raise ValueError(f"default branch is missing for {repository['name']}")
        observed[repository["name"]] = live
    return observed


def resolve_consumer_pin(repository, observed, api):
    """Read, never execute, one consumer's default-branch SDLC flake pin."""
    branch = observed["default_branch"]
    lock = api.get(
        f"repos/blogle/{repository['name']}/contents/flake.lock?ref={branch}"
    )
    if lock.get("encoding") != "base64" or not isinstance(lock.get("content"), str):
        raise ValueError(f"{repository['name']}: default-branch flake.lock is unavailable")
    try:
        document = json.loads(base64.b64decode(lock["content"]).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"{repository['name']}: default-branch flake.lock is invalid") from error
    try:
        input_name = document["nodes"]["root"]["inputs"]["sdlc"]
        node = document["nodes"][input_name]
        locked = node["locked"]
        original = node.get("original", {})
    except (KeyError, TypeError):
        raise ValueError(f"{repository['name']}: flake.lock has no sdlc input")
    if (
        locked.get("type") != "github"
        or locked.get("owner") != "blogle"
        or locked.get("repo") != "sdlc"
        or not SHA_RE.fullmatch(str(locked.get("rev", "")))
    ):
        raise ValueError(f"{repository['name']}: sdlc lock identity is not trusted")
    ref = original.get("ref", "")
    if ref and not (SHA_RE.fullmatch(str(ref)) or re.fullmatch(r"v\d+\.\d+\.\d+", str(ref))):
        raise ValueError(f"{repository['name']}: sdlc lock ref is not immutable")
    commit = api.get(f"repos/blogle/sdlc/commits/{locked['rev']}")
    if commit.get("sha") != locked["rev"]:
        raise ValueError(f"{repository['name']}: sdlc revision is unavailable")
    compare = api.get(f"repos/blogle/sdlc/compare/{locked['rev']}...main")
    if compare.get("status") not in ("ahead", "identical") or compare.get("behind_by") != 0:
        raise ValueError(f"{repository['name']}: sdlc pin is not an ancestor of protected main")
    return {"revision": locked["rev"], "ref": ref or None}


def repository_plan(repository):
    identity_key = f"{repository['name']}:{repository['id']}"
    if repository.get("suspended", False) or repository.get("state") == "suspended":
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
    """Prepare environment-secret metadata only; never fall back to repo secrets."""
    with RELEASE_CREDENTIALS.open(encoding="utf-8") as stream:
        contract = json.load(stream)
    return prepare_release_app_distribution_for_contract(repository, api, contract)


def prepare_release_app_distribution_for_contract(repository, api, contract):
    """Select a safe credential path from observed permission/wiring metadata."""
    owner = "blogle"
    permissions = contract.get("observed_permissions", {})
    workflow = contract.get("observed_workflow", {})
    if permissions.get("environments") != "write":
        return {
            "name": repository["name"],
            "state": "unknown",
            "reason": "Environments: write is required for environment secret propagation",
            "repository_secret_fallback": False,
            "write": False,
        }
    if (
        workflow.get("called_job_environment") != contract.get("environment")
        or workflow.get("reads_environment_secrets") is not True
    ):
        return {
            "name": repository["name"],
            "state": "unsafe",
            "reason": "release workflow does not explicitly wire environment secrets",
            "repository_secret_fallback": False,
            "write": False,
        }
    current = api.get(
        f"repos/{owner}/{repository['name']}/environments/{contract['environment']}/secrets"
    )
    names = sorted(item.get("name", "") for item in current.get("secrets", []))
    return {
        "name": repository["name"],
        "state": "prepared",
        "operation": "upsert-protected-release-environment-secrets",
        "required_names": ["SDLC_RELEASE_APP_ID", "SDLC_RELEASE_APP_PRIVATE_KEY"],
        "existing_names": names,
        "repository_secret_fallback": False,
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


def sdlc_adapter(mode, manifest_path, policy_path, attestation_path, consumer_pin, floor):
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
        "--manifest",
        str(manifest_path),
        controller["policy_flag"],
        str(policy_path),
        "--attestation",
        str(attestation_path),
        "--consumer-pin",
        consumer_pin,
        controller["trusted_bypass_flag"],
        str(bypass_id),
    ]
    result = subprocess.run(command, text=True)
    if result.returncode == 0:
        return {"state": "prepared", "ready": False, "activation": "unchanged", "exit": 0}
    return {"state": "unsafe", "ready": False, "exit": result.returncode}


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
            observed = verify_live_identities(manifest, GitHubAPI())
        except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
            return fail(f"live identity preflight failed: {error}")
        with tempfile.TemporaryDirectory(prefix="fleet-prepare-") as directory:
            try:
                verify_controller_pin(GitHubAPI())
            except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
                return fail(f"trusted controller preflight failed: {error}")
            results = {}
            for repository in manifest["repositories"]:
                if not repository["enabled"] or repository.get("state") == "suspended":
                    results[repository["name"]] = repository_plan(repository)
                    continue
                try:
                    consumer = resolve_consumer_pin(repository, observed[repository["name"]], GitHubAPI())
                    policy = json.loads(POLICY.read_text(encoding="utf-8"))
                    policy["provenance"]["revision"] = consumer["revision"]
                    policy["bypass"]["user_id"] = floor["human_bypass_actor_id"]
                    policy["bypass"]["actors"] = [floor["human_bypass_actor_id"]]
                    policy["bypass"]["count"] = 1
                    policy_path = Path(directory) / f"{repository['name']}-policy.json"
                    manifest_path = Path(directory) / f"{repository['name']}-manifest.json"
                    attestation_path = Path(directory) / f"{repository['name']}-attestation.json"
                    policy_path.write_text(json.dumps(policy), encoding="utf-8")
                    manifest_path.write_text(json.dumps({**manifest, "repositories": [repository]}), encoding="utf-8")
                    attestation_path.write_text(json.dumps({
                        "source": "blogle/sdlc",
                        "repository_id": 1402311485,
                        "commit_sha": consumer["revision"],
                        "reachable_from_protected": True,
                        "immutable": True,
                        "verified_by": "dotfiles-trusted-controller",
                    }), encoding="utf-8")
                    results[repository["name"]] = sdlc_adapter(
                        "reconcile", manifest_path, policy_path, attestation_path,
                        consumer["revision"], floor
                    ) | {"consumer_pin": consumer}
                except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
                    results[repository["name"]] = {"state": "unknown", "reason": str(error)}
            print(json.dumps({"state": "prepared", "ready": False, "repositories": results}, sort_keys=True))
            return 0 if all(item.get("state") in ("prepared", "suspended", "disabled") for item in results.values()) else 1

    result = {"state": "prepare-only", "repositories": [repository_plan(item) for item in manifest["repositories"]]}
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
