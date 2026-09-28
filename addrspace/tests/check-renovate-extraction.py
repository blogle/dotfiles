#!/usr/bin/env python3
"""Assert Renovate's real local extraction still covers critical GitOps inputs."""

import json
import os
from pathlib import Path
import re
import subprocess

import json5


ROOT = Path(__file__).resolve().parents[2]


def extracted_files(log):
    marker = '"packageFiles": {'
    start = log.index(marker, log.index("INFO: Extracted dependencies"))
    end = log.index("\nDEBUG:", start)
    return json.loads("{" + log[start:end].strip() + "}")["packageFiles"]


def dependencies(files, manager, package_file):
    return [
        dep
        for record in records(files, manager, package_file)
        for dep in record.get("deps", [])
    ]


def records(files, manager, package_file):
    return [
        record
        for record in files.get(manager, [])
        if record.get("packageFile") == package_file
    ]


def require_dep(files, manager, package_file, dep_name, datasource):
    matches = [
        dep
        for dep in dependencies(files, manager, package_file)
        if dep.get("depName") == dep_name and dep.get("datasource") == datasource
    ]
    assert matches, f"Missing {manager} {datasource} dependency {dep_name} in {package_file}"
    return matches


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
        for file in files.get("regex", [])
        if file.get("packageFile", "").startswith("addrspace/")
        for dep in file.get("deps", [])
        if dep.get("datasource") == "helm"
    }
    assert {"external-dns", "alloy", "grafana", "loki", "tempo"} <= rancher_charts

    anvil_file = "addrspace/apps/anvil/kustomization.yaml"
    anvil = require_dep(files, "regex", anvil_file, "blogle/anvil", "git-refs")
    assert len(anvil) == 1, f"Anvil application must extract as one coupled dependency, got {len(anvil)}"
    assert anvil[0].get("currentDigest") == "13334d5709a6a9f1f1c8894da33b8ef09565a3df"
    replace_string = anvil[0].get("replaceString", "")
    assert "github.com/blogle/anvil//k8s/base?ref=" in replace_string
    assert replace_string.count("newTag: sha-") == 2
    anvil_revisions = re.findall(r"(?:ref=|newTag: sha-)([a-f0-9]{40})", replace_string)
    assert len(anvil_revisions) == 3 and len(set(anvil_revisions)) == 1
    anvil_records = records(files, "regex", anvil_file)
    assert len(anvil_records) == 1
    assert anvil_records[0].get("autoReplaceStringTemplate", "").count("{{{newDigest}}}") == 3
    require_dep(
        files,
        "regex",
        "addrspace/controllers/agent-sandbox/kustomization.yaml",
        "blogle/anvil",
        "git-refs",
    )
    prod = require_dep(
        files,
        "regex",
        "addrspace/apps/dojo/overlays/prod/kustomization.yaml",
        "blogle/dojo2",
        "git-refs",
    )
    assert len(prod) == 1
    prod_image = require_dep(
        files,
        "kustomize",
        "addrspace/apps/dojo/overlays/prod/kustomization.yaml",
        "ghcr.io/blogle/dojo2",
        "docker",
    )
    assert prod_image[0].get("currentDigest", "").startswith("sha256:")
    staging = require_dep(
        files,
        "regex",
        "addrspace/apps/dojo/overlays/staging/kustomization.yaml",
        "blogle/dojo2",
        "git-refs",
    )
    assert len(staging) == 1
    assert "newTag: git-" in staging[0].get("replaceString", "")

    image_deps = [
        dep
        for file in files.get("kubernetes", [])
        for dep in file.get("deps", [])
        if dep.get("datasource") == "docker"
    ]
    assert image_deps, "No standard Kubernetes container images extracted"

    config = json5.loads((ROOT / "renovate.json5").read_text())
    rules = config["packageRules"]
    anvil_image_names = {"ghcr.io/blogle/anvil", "ghcr.io/blogle/anvil-sandbox"}
    assert any(
        rule.get("enabled") is False
        and {"kubernetes", "kustomize"} <= set(rule.get("matchManagers", []))
        and anvil_image_names <= set(rule.get("matchPackageNames", []))
        for rule in rules
    ), "Anvil image dependencies must not update independently of the coupled regex dependency"
    assert any(
        rule.get("enabled") is False
        and "kustomize" in rule.get("matchManagers", [])
        and "ghcr.io/blogle/dojo2" in rule.get("matchPackageNames", [])
        and "addrspace/apps/dojo/overlays/staging/kustomization.yaml" in rule.get("matchFileNames", [])
        for rule in rules
    ), "Dojo staging image must not update independently of its coupled base revision"
    assert any(
        rule.get("enabled") is False
        and "kubernetes" in rule.get("matchManagers", [])
        and "ghcr.io/blogle/dojo2" in rule.get("matchPackageNames", [])
        and {
            "addrspace/apps/dojo/overlays/prod/pod-spec.patch.yaml",
            "addrspace/apps/dojo/overlays/staging/pod-spec.patch.yaml",
        } <= set(rule.get("matchFileNames", []))
        for rule in rules
    ), "Dojo patch image references must not become independent updates"

    print("Renovate extraction coverage passed: Flux, Sealed Secrets, cert-manager, MetalLB,")
    print("OpenEBS ZFS LocalPV, kube-prometheus-stack, Rancher HelmCharts, Anvil, Agent Sandbox,")
    print("Dojo prod/staging, and regular Kubernetes container images.")


if __name__ == "__main__":
    main()
