#!/usr/bin/env python3
"""Assert Renovate's real extraction preserves the addrspace update policies."""

import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import json5


ROOT = Path(__file__).resolve().parents[2]
ANVIL_IMAGES = {"ghcr.io/blogle/anvil", "ghcr.io/blogle/anvil-sandbox"}
DOJO_IMAGE = "ghcr.io/blogle/dojo2"
DOJO_PROD_FILES = (
    "addrspace/apps/dojo/overlays/prod/kustomization.yaml",
    "addrspace/apps/dojo/overlays/prod/pod-spec.patch.yaml",
)


def extracted_files(log):
    marker = '"packageFiles": {'
    start = log.index(marker, log.index("INFO: Extracted dependencies"))
    end = log.index("\nDEBUG:", start)
    return json.loads("{" + log[start:end].strip() + "}")["packageFiles"]


def records(files, manager, package_file):
    return [
        record
        for record in files.get(manager, [])
        if record.get("packageFile") == package_file
    ]


def dependencies(files, manager, package_file):
    return [dep for record in records(files, manager, package_file) for dep in record.get("deps", [])]


def require_dep(files, manager, package_file, dep_name, datasource):
    matches = [
        dep
        for dep in dependencies(files, manager, package_file)
        if dep.get("depName") == dep_name and dep.get("datasource") == datasource
    ]
    assert matches, f"Missing {manager} {datasource} dependency {dep_name} in {package_file}"
    return matches


def disabled_by_rule(rules, manager, package_file, package_name):
    return any(
        rule.get("enabled") is False
        and manager in rule.get("matchManagers", [])
        and package_name in rule.get("matchPackageNames", [])
        and any(fnmatch.fnmatchcase(package_file, pattern) for pattern in rule.get("matchFileNames", ["**"]))
        for rule in rules
    )


def assert_manager_sources_are_disabled(files, rules, managers, package_files, package_names):
    for manager in managers:
        for record in files.get(manager, []):
            package_file = record.get("packageFile", "")
            if package_file not in package_files:
                continue
            for dep in record.get("deps", []):
                package_name = dep.get("packageName") or dep.get("depName")
                if package_name in package_names:
                    assert disabled_by_rule(rules, manager, package_file, package_name), (
                        f"{manager} can independently update {package_name} from {package_file}"
                    )


def registry_release_fixture():
    repository = "blogle/dojo2"
    query = urlencode({"scope": f"repository:{repository}:pull", "service": "ghcr.io"})
    with urlopen(f"https://ghcr.io/token?{query}", timeout=15) as response:
        token = json.load(response)["token"]
    request = Request(
        f"https://ghcr.io/v2/{repository}/tags/list",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urlopen(request, timeout=20) as response:
        tags = json.load(response)["tags"]
    releases = sorted(
        (tag for tag in tags if re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag)),
        key=lambda tag: tuple(int(part) for part in tag[1:].split(".")),
    )
    if len(releases) < 2:
        raise AssertionError("Need two published Dojo semantic images to exercise a Renovate update")
    fixture_tag = releases[0]
    manifest_request = Request(
        f"https://ghcr.io/v2/{repository}/manifests/{fixture_tag}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": ", ".join(
                (
                    "application/vnd.oci.image.index.v1+json",
                    "application/vnd.oci.image.manifest.v1+json",
                    "application/vnd.docker.distribution.manifest.list.v2+json",
                    "application/vnd.docker.distribution.manifest.v2+json",
                )
            ),
        },
    )
    with urlopen(manifest_request, timeout=20) as response:
        fixture_digest = response.headers.get("Docker-Content-Digest")
    if not fixture_digest or not re.fullmatch(r"sha256:[a-f0-9]{64}", fixture_digest):
        raise AssertionError(f"No immutable digest for fixture release {fixture_tag}")
    return fixture_tag, fixture_digest


def assert_renovate_proposes_one_staging_release(current_release):
    """Run Renovate's update pipeline on a throwaway old-release fixture."""
    fixture_tag, fixture_digest = registry_release_fixture()
    if fixture_tag == current_release:
        raise AssertionError("The checked-out Dojo staging release is not newer than the update fixture")

    with tempfile.TemporaryDirectory(prefix="renovate-dojo-release-") as temporary:
        checkout = Path(temporary) / "checkout"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(ROOT), str(checkout)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        manifest = checkout / "addrspace/apps/dojo/overlays/staging/kustomization.yaml"
        content = manifest.read_text()
        content, base_count = re.subn(r"(ref=)v[0-9]+\.[0-9]+\.[0-9]+", rf"\g<1>{fixture_tag}", content, count=1)
        content, tag_count = re.subn(r"(newTag:\s*)v[0-9]+\.[0-9]+\.[0-9]+", rf"\g<1>{fixture_tag}", content, count=1)
        content, digest_count = re.subn(r"(digest:\s*)sha256:[a-f0-9]{64}", rf"\g<1>{fixture_digest}", content, count=1)
        if (base_count, tag_count, digest_count) != (1, 1, 1):
            raise AssertionError("Could not construct the old semantic release fixture")
        manifest.write_text(content)
        subprocess.run(["git", "add", str(manifest.relative_to(checkout))], cwd=checkout, check=True)
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=Renovate extraction test",
                "-c",
                "user.email=renovate-test@example.invalid",
                "commit",
                "--quiet",
                "-m",
                "test fixture: old Dojo semantic release",
            ],
            cwd=checkout,
            check=True,
        )

        env = os.environ.copy()
        env["LOG_LEVEL"] = "debug"
        env["RENOVATE_BASE_DIR"] = str(Path(temporary) / "renovate-cache")
        result = subprocess.run(
            [
                "npx",
                "--yes",
                "--package",
                "renovate",
                "renovate",
                "--platform=local",
                "--dry-run=full",
                "--include-paths=addrspace/apps/dojo/overlays/staging/kustomization.yaml",
            ],
            cwd=checkout,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=True,
        )
        output = result.stdout
        updates_marker = "packageFiles with updates"
        if updates_marker not in output or f'"packageFile": "addrspace/apps/dojo/overlays/staging/kustomization.yaml"' not in output:
            raise AssertionError(
                f"Renovate did not produce a staging update from {fixture_tag}:\n{output[-5000:]}"
            )
        if f'"currentValue": "{fixture_tag}"' not in output or f'"newValue": "{current_release}"' not in output:
            raise AssertionError(
                f"Renovate did not advance the staging fixture to {current_release}:\n{output[-5000:]}"
            )
        if output.count('"packageFile": "addrspace/apps/dojo/overlays/staging/kustomization.yaml"') < 2:
            raise AssertionError("Expected one extracted dependency and one update record for staging")


def main():
    env = os.environ.copy()
    env["LOG_LEVEL"] = "debug"
    result = subprocess.run(
        ["npx", "--yes", "--package", "renovate", "renovate", "--platform=local", "--dry-run=extract"],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    files = extracted_files(result.stdout)

    require_dep(
        files,
        "flux",
        "addrspace/clusters/addrspace/flux-system/gotk-components.yaml",
        "fluxcd/flux2",
        "github-releases",
    )
    require_dep(files, "regex", "addrspace/controllers/kustomization.yaml", "bitnami-labs/sealed-secrets", "github-releases")
    require_dep(files, "regex", "addrspace/controllers/cert-manager.yaml", "cert-manager", "helm")
    require_dep(files, "kustomize", "addrspace/controllers/metallb/kustomization.yaml", "metallb/metallb", "github-tags")
    require_dep(files, "regex", "addrspace/controllers/zfs-localpv.yaml", "zfs-localpv", "helm")
    require_dep(files, "regex", "addrspace/controllers/kube-prometheus-stack.yaml", "kube-prometheus-stack", "helm")

    rancher_charts = {
        dep.get("depName")
        for record in files.get("regex", [])
        if record.get("packageFile", "").startswith("addrspace/")
        for dep in record.get("deps", [])
        if dep.get("datasource") == "helm"
    }
    assert {"external-dns", "alloy", "grafana", "loki", "tempo"} <= rancher_charts

    config = json5.loads((ROOT / "renovate.json5").read_text())
    rules = config["packageRules"]
    anvil_file = "addrspace/apps/anvil/kustomization.yaml"

    # Anvil: a single custom git-refs dependency couples a valid SHA to all three
    # desired-state values. Generic image managers may extract, but cannot update.
    anvil = require_dep(files, "regex", anvil_file, "blogle/anvil", "git-refs")
    assert len(anvil) == 1, f"Expected one coupled Anvil dependency, got {len(anvil)}"
    anvil_sha = anvil[0].get("currentDigest", "")
    assert re.fullmatch(r"[a-f0-9]{40}", anvil_sha), "Anvil main revision must be a full Git SHA"
    anvil_record = records(files, "regex", anvil_file)
    assert len(anvil_record) == 1
    anvil_replace = anvil[0].get("replaceString", "")
    revisions = re.findall(r"(?:ref=|newTag: sha-)([a-f0-9]{40})", anvil_replace)
    assert len(revisions) == 3 and revisions == [anvil_sha] * 3
    assert anvil_record[0].get("autoReplaceStringTemplate", "").count("{{{newDigest}}}") == 3
    assert anvil[0].get("currentValue") == "main"
    require_dep(
        files,
        "regex",
        "addrspace/controllers/agent-sandbox/kustomization.yaml",
        "blogle/anvil",
        "git-refs",
    )
    assert_manager_sources_are_disabled(
        files,
        rules,
        ("kubernetes", "kustomize"),
        (anvil_file, "addrspace/apps/anvil/profile-deployment.patch.yaml"),
        ANVIL_IMAGES,
    )

    # Dojo staging: semantic docker releases are the sole custom dependency.
    # The regex replacement advances the Git base and image tag together and
    # carries the resolved image digest in that same update.
    staging_file = "addrspace/apps/dojo/overlays/staging/kustomization.yaml"
    staging = require_dep(files, "regex", staging_file, DOJO_IMAGE, "docker")
    assert len(staging) == 1, f"Expected one coupled Dojo staging release, got {len(staging)}"
    current_release = staging[0].get("currentValue", "")
    assert re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", current_release)
    assert re.fullmatch(r"sha256:[a-f0-9]{64}", staging[0].get("currentDigest", ""))
    staging_record = records(files, "regex", staging_file)
    assert len(staging_record) == 1
    staging_replace = staging[0].get("replaceString", "")
    assert re.findall(r"ref=(v[0-9]+\.[0-9]+\.[0-9]+)", staging_replace) == [current_release]
    assert re.findall(r"newTag:\s*(v[0-9]+\.[0-9]+\.[0-9]+)", staging_replace) == [current_release]
    assert staging_record[0].get("autoReplaceStringTemplate", "").count("{{{newValue}}}") == 2
    assert staging_record[0].get("autoReplaceStringTemplate", "").count("{{{newDigest}}}") == 1
    assert not re.search(r"ref=(master|main|[a-f0-9]{40})|newTag:\s*(staging|git-)", staging_replace)
    assert any(
        manager.get("customType") == "regex"
        and "staging" in " ".join(manager.get("managerFilePatterns", []))
        and manager.get("datasourceTemplate") == "docker"
        and manager.get("versioningTemplate") == "semver"
        for manager in config.get("customManagers", [])
    ), "Dojo staging must use semantic Docker releases, not master Git refs"
    assert_renovate_proposes_one_staging_release(current_release)
    assert any(
        rule.get("automerge") is True and "custom.regex" in rule.get("matchManagers", [])
        for rule in rules
    ), "The semantic-release dependency must remain eligible for required-check automerge"
    assert_manager_sources_are_disabled(
        files,
        rules,
        ("kubernetes", "kustomize"),
        (staging_file, "addrspace/apps/dojo/overlays/staging/pod-spec.patch.yaml"),
        {DOJO_IMAGE},
    )

    # Dojo production: generic managers may identify the inputs during raw
    # extraction, but a file-scoped disabled rule prevents application updates.
    assert not any(
        "addrspace/apps/dojo/overlays/prod/kustomization.yaml" in pattern
        for manager in config.get("customManagers", [])
        for pattern in manager.get("managerFilePatterns", [])
        if "dojo" in pattern
    ), "Dojo production must not have a Renovate custom update manager"
    prod_deps = [
        (manager, package_file, package_name)
        for manager in ("kubernetes", "kustomize")
        for record in files.get(manager, [])
        for package_file in (record.get("packageFile", ""),)
        if package_file in DOJO_PROD_FILES
        for dep in record.get("deps", [])
        for package_name in (dep.get("packageName") or dep.get("depName"),)
        if package_name in {"blogle/dojo2", DOJO_IMAGE}
    ]
    assert prod_deps, "Expected Renovate's generic managers to see the manually pinned prod inputs"
    for manager, package_file, package_name in prod_deps:
        assert disabled_by_rule(rules, manager, package_file, package_name), (
            f"Dojo production update is not explicitly disabled: {manager} {package_name} in {package_file}"
        )

    normal_images = [
        dep
        for record in files.get("kubernetes", [])
        for dep in record.get("deps", [])
        if dep.get("datasource") == "docker"
    ]
    assert normal_images, "No normal Kubernetes container images were extracted"

    print("Renovate extraction policy passed: Anvil main is coupled; Dojo staging is semantic-release coupled;")
    print("Dojo prod is explicitly excluded; Flux, controllers, Rancher charts, Agent Sandbox, and workload images remain discoverable.")


if __name__ == "__main__":
    main()
