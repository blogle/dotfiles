#!/usr/bin/env python3
"""Assert Renovate's real extraction preserves the addrspace update policies."""

import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import json5


ROOT = Path(__file__).resolve().parents[2]
ANVIL_IMAGES = {"ghcr.io/blogle/anvil", "ghcr.io/blogle/anvil-sandbox", "ghcr.io/blogle/anvil-nix-daemon"}
DOJO_IMAGE = "ghcr.io/blogle/dojo2"
DOJO_PROD_FILES = (
    "addrspace/apps/dojo/overlays/prod/kustomization.yaml",
    "addrspace/apps/dojo/overlays/prod/pod-spec.patch.yaml",
)


def anvil_manager(config):
    return next(
        manager
        for manager in config["customManagers"]
        if manager.get("description", "").startswith("Anvil main base")
    )


def anvil_match(manager, content):
    pattern = manager["matchStrings"][0].replace("(?<", "(?P<")
    return re.search(pattern, content)


def render_anvil_replacement(manager, match, new_digest):
    values = {**match.groupdict(), "newDigest": new_digest}
    return re.sub(
        r"\{\{\{(\w+)\}\}\}",
        lambda placeholder: values[placeholder.group(1)],
        manager["autoReplaceStringTemplate"],
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


def registry_release_fixture(current_tag):
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
    target_tag = releases[-1]
    fixture_candidates = [tag for tag in releases[:-1] if tag != current_tag]
    if not fixture_candidates:
        raise AssertionError(
            f"Need a published Dojo semantic image distinct from current staging tag {current_tag}"
        )
    fixture_tag = fixture_candidates[-1]
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
    return fixture_tag, fixture_digest, target_tag


def assert_anvil_accepts_arbitrary_sha_fixture(current_sha):
    fixture_sha = "a" * 40 if current_sha != "a" * 40 else "b" * 40
    with tempfile.TemporaryDirectory(prefix="renovate-anvil-sha-test-") as temporary:
        checkout = Path(temporary) / "checkout"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(ROOT), str(checkout)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        manifest = checkout / "addrspace/apps/anvil/kustomization.yaml"
        content, count = re.subn(
            r"(?<=ref=)[a-f0-9]{40}|(?<=newTag: sha-)[a-f0-9]{40}|(?<=newTag: \"sha-)[a-f0-9]{40}",
            fixture_sha,
            manifest.read_text(),
        )
        if count != 4:
            raise AssertionError(f"Expected four Anvil SHA fields in fixture, found {count}")
        manifest.write_text(content)
        manager = anvil_manager(json5.loads((ROOT / "renovate.json5").read_text()))
        match = anvil_match(manager, content)
        if not match:
            raise AssertionError("Anvil regex did not span the complete four-SHA fixture")
        revisions = re.findall(r"(?:ref=|newTag:\s*[\"]?sha-)([a-f0-9]{40})", match.group(0))
        if revisions != [fixture_sha] * 4:
            raise AssertionError("Anvil regex did not capture all four coupled SHA fields")
        replacement = render_anvil_replacement(manager, match, "b" * 40)
        if re.findall(r"(?:ref=|newTag:\s*[\"]?sha-)([a-f0-9]{40})", replacement) != ["b" * 40] * 4:
            raise AssertionError("Anvil replacement template did not preserve four-way SHA coupling")
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
                "test fixture: arbitrary Anvil SHA",
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
                "--dry-run=extract",
                "--include-paths=addrspace/apps/anvil/kustomization.yaml",
            ],
            cwd=checkout,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=True,
        )
        fixture_files = extracted_files(result.stdout)
        fixture_dep = require_dep(
            fixture_files,
            "regex",
            "addrspace/apps/anvil/kustomization.yaml",
            "blogle/anvil",
            "git-refs",
        )
        if len(fixture_dep) != 1 or fixture_dep[0].get("currentDigest") != fixture_sha:
            raise AssertionError("Anvil extractor rejected an arbitrary valid SHA fixture")
    print("Anvil extraction accepts an arbitrary 40-character SHA and keeps all four values coupled.")


def assert_renovate_proposes_one_anvil_update():
    """Run Renovate's full update pipeline on a stale Anvil fixture."""
    fixture_sha = "a" * 40

    with tempfile.TemporaryDirectory(prefix="renovate-anvil-update-") as temporary:
        checkout = Path(temporary) / "checkout"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(ROOT), str(checkout)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        manifest = checkout / "addrspace/apps/anvil/kustomization.yaml"
        content, count = re.subn(
            r"(?<=ref=)[a-f0-9]{40}|(?<=newTag: sha-)[a-f0-9]{40}|(?<=newTag: \"sha-)[a-f0-9]{40}",
            fixture_sha,
            manifest.read_text(),
        )
        if count != 4:
            raise AssertionError(f"Expected four Anvil SHA fields in fixture, found {count}")
        manifest.write_text(content)
        shutil.copy(ROOT / "renovate.json5", checkout / "renovate.json5")
        config = json5.loads((checkout / "renovate.json5").read_text())
        manager = anvil_manager(config)
        if not anvil_match(manager, content):
            raise AssertionError("Anvil update fixture does not match its configured regex")
        subprocess.run(
            ["git", "add", str(manifest.relative_to(checkout)), "renovate.json5"],
            cwd=checkout,
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=Renovate update test",
                "-c",
                "user.email=renovate-test@example.invalid",
                "commit",
                "--quiet",
                "-m",
                "test fixture: stale Anvil main",
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
                "--include-paths=addrspace/apps/anvil/kustomization.yaml",
            ],
            cwd=checkout,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        output = result.stdout
        if result.returncode != 0:
            raise AssertionError(f"Renovate Anvil full update failed:\n{output[-10000:]}")
        if (
            "packageFiles with updates" not in output
            or '"depName": "blogle/anvil"' not in output
            or '"branchName": "renovate/blogle-anvil-digest"' not in output
            or "WORKER_FILE_UPDATE_FAILED" in output
            or "Error updating branch: update failure" in output
        ):
            raise AssertionError("Renovate full dry-run did not recognize the Anvil update")
        target_matches = re.findall(r'"newDigest":\s*"([a-f0-9]{40})"', output)
        if not target_matches or target_matches[0] == fixture_sha:
            raise AssertionError(f"Renovate did not resolve a new Anvil main SHA:\n{output[-10000:]}")
        target_sha = target_matches[0]
        match = anvil_match(manager, content)
        if not match:
            raise AssertionError("Anvil update fixture does not match its configured regex")

        updated_content = content.replace(match.group(0), render_anvil_replacement(manager, match, target_sha))
        if re.findall(r"(?:ref=|newTag:\s*[\"]?sha-)([a-f0-9]{40})", updated_content) != [target_sha] * 4:
            raise AssertionError("Renovate update did not preserve the four-way Anvil SHA coupling")
        print(f"Renovate full dry-run and rendered replacement preserve Anvil coupling: {fixture_sha} -> {target_sha}")


def assert_renovate_proposes_one_staging_release():
    """Run Renovate's update pipeline on a throwaway old-release fixture."""
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
        current_match = re.search(r"newTag:\s*(v[0-9]+\.[0-9]+\.[0-9]+)", content)
        if not current_match:
            raise AssertionError("Could not determine current Dojo staging semantic release")
        fixture_tag, fixture_digest, target_tag = registry_release_fixture(current_match.group(1))
        content, base_count = re.subn(r"(ref=)v[0-9]+\.[0-9]+\.[0-9]+", rf"\g<1>{fixture_tag}", content, count=1)
        content, tag_count = re.subn(r"(newTag:\s*)v[0-9]+\.[0-9]+\.[0-9]+", rf"\g<1>{fixture_tag}", content, count=1)
        content, digest_count = re.subn(r"(digest:\s*)sha256:[a-f0-9]{64}", rf"\g<1>{fixture_digest}", content, count=1)
        if (base_count, tag_count, digest_count) != (1, 1, 1):
            raise AssertionError("Could not construct the old semantic release fixture")
        manifest.write_text(content)
        fixture_config_path = checkout / "renovate.json5"
        fixture_config = json5.loads(fixture_config_path.read_text())
        fixture_config["packageRules"].append(
            {
                "matchPackageNames": [DOJO_IMAGE],
                "allowedVersions": target_tag,
            }
        )
        fixture_config_path.write_text(json.dumps(fixture_config, indent=2) + "\n")
        subprocess.run(
            ["git", "add", str(manifest.relative_to(checkout)), str(fixture_config_path.relative_to(checkout))],
            cwd=checkout,
            check=True,
        )
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
        if f'"currentValue": "{fixture_tag}"' not in output or f'"newValue": "{target_tag}"' not in output:
            raise AssertionError(
                f"Renovate did not advance the staging fixture to {target_tag}:\n{output[-5000:]}"
            )
        if not re.search(r'"newDigest":\s*"sha256:[a-f0-9]{64}"', output):
            raise AssertionError("Renovate did not resolve an immutable digest for the target Dojo release")
        if output.count('"packageFile": "addrspace/apps/dojo/overlays/staging/kustomization.yaml"') < 2:
            raise AssertionError("Expected one extracted dependency and one update record for staging")
        print(f"Renovate dry-run proposes one coherent staging update: {fixture_tag} -> {target_tag}")


def assert_renovate_does_not_propose_prod_update():
    with tempfile.TemporaryDirectory(prefix="renovate-dojo-prod-test-") as temporary:
        checkout = Path(temporary) / "checkout"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", str(ROOT), str(checkout)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
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
                "--include-paths=addrspace/apps/dojo/overlays/prod/kustomization.yaml,addrspace/apps/dojo/overlays/prod/pod-spec.patch.yaml",
            ],
            cwd=checkout,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=True,
        )
        if "DRY-RUN: Would create branch" in result.stdout or "DRY-RUN: Would create PR" in result.stdout:
            raise AssertionError(f"Renovate proposed an automatic Dojo prod update:\n{result.stdout[-5000:]}")
        print("Renovate full dry-run proposes no automatic Dojo production update.")


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
    require_dep(files, "regex", "addrspace/platform/observability/clickstack/helmchart.yaml", "clickstack", "helm")
    require_dep(files, "regex", "addrspace/platform/observability/clickstack-operators/helmchart.yaml", "clickstack-operators", "helm")

    rancher_charts = {
        dep.get("depName")
        for record in files.get("regex", [])
        if record.get("packageFile", "").startswith("addrspace/")
        for dep in record.get("deps", [])
        if dep.get("datasource") == "helm"
    }
    assert {"external-dns", "clickstack", "clickstack-operators"} <= rancher_charts
    assert not ({"alloy", "grafana", "loki", "tempo", "kube-prometheus-stack"} & rancher_charts)

    config = json5.loads((ROOT / "renovate.json5").read_text())
    rules = config["packageRules"]
    anvil_file = "addrspace/apps/anvil/kustomization.yaml"

    # Anvil: a single custom git-refs dependency couples a valid SHA to all four
    # desired-state values. Generic image managers may extract, but cannot update.
    anvil = require_dep(files, "regex", anvil_file, "blogle/anvil", "git-refs")
    assert len(anvil) == 1, f"Expected one coupled Anvil dependency, got {len(anvil)}"
    anvil_sha = anvil[0].get("currentDigest", "")
    assert re.fullmatch(r"[a-f0-9]{40}", anvil_sha), "Anvil main revision must be a full Git SHA"
    anvil_record = records(files, "regex", anvil_file)
    assert len(anvil_record) == 1
    manager = anvil_manager(config)
    match = anvil_match(manager, (ROOT / anvil_file).read_text())
    assert match, "Anvil regex must span the complete base and four image SHA fields"
    revisions = re.findall(r"(?:ref=|newTag:\s*[\"]?sha-)([a-f0-9]{40})", match.group(0))
    assert len(revisions) == 4 and revisions == [anvil_sha] * 4
    replacement = render_anvil_replacement(manager, match, "b" * 40)
    assert re.findall(r"(?:ref=|newTag:\s*[\"]?sha-)([a-f0-9]{40})", replacement) == ["b" * 40] * 4
    assert anvil[0].get("currentValue") == "main"
    assert_anvil_accepts_arbitrary_sha_fixture(anvil_sha)
    assert_renovate_proposes_one_anvil_update()
    vendor = require_dep(
        files,
        "regex",
        "addrspace/controllers/agent-sandbox/kustomization.yaml",
        "blogle/anvil-agent-sandbox",
        "git-refs",
    )
    assert vendor[0].get("packageName") == "https://github.com/blogle/anvil"
    assert vendor[0].get("currentValue") == "main"
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
    assert_renovate_proposes_one_staging_release()
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
    assert_renovate_does_not_propose_prod_update()

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
