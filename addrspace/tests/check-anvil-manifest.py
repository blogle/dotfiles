#!/usr/bin/env python3
"""Validate production Anvil storage and immutable image parity."""

import re
import subprocess
from pathlib import Path

import yaml


def nix_claim(resource):
    if resource["kind"] == "Deployment":
        pod_spec = resource["spec"]["template"]["spec"]
    else:
        pod_spec = resource["spec"]["jobTemplate"]["spec"]["template"]["spec"]
    volumes = {volume["name"]: volume for volume in pod_spec.get("volumes", [])}
    return volumes["nix"]["persistentVolumeClaim"]["claimName"]


rendered = subprocess.check_output(["kubectl", "kustomize", "addrspace/apps/anvil"], text=True)
resources = [resource for resource in yaml.safe_load_all(rendered) if resource]
selected = {(resource["kind"], resource["metadata"]["name"]): resource for resource in resources}

for key in (("Deployment", "anvil-nix-daemon"), ("CronJob", "anvil-nix-gc")):
    assert nix_claim(selected[key]) == "anvil-nix-shared", f"{key} must use anvil-nix-shared"

controller_image = selected[("Deployment", "anvild")]["spec"]["template"]["spec"]["containers"][0]["image"]
profile_image = selected[("Deployment", "anvil-profile")]["spec"]["template"]["spec"]["containers"][0]["image"]
sandbox_image = selected[("ConfigMap", "anvil-runtime")]["data"]["ANVIL_SANDBOX_IMAGE"]
assert sandbox_image == profile_image, "runtime sandbox image must match the post-transform profile image"
controller_match = re.fullmatch(r"ghcr\.io/blogle/anvil:sha-([0-9a-f]{40})", controller_image)
profile_match = re.fullmatch(r"ghcr\.io/blogle/anvil-sandbox:sha-([0-9a-f]{40})", profile_image)
assert controller_match, controller_image
assert profile_match, profile_image
anvil_kustomization = yaml.safe_load(Path("addrspace/apps/anvil/kustomization.yaml").read_text())
base_ref_match = re.search(r"//k8s/base\?ref=([0-9a-f]{40})$", anvil_kustomization["resources"][0])
assert base_ref_match, "Anvil base resource must pin an immutable upstream SHA"
assert controller_match.group(1) == profile_match.group(1) == base_ref_match.group(1), (
    "controller image, profile image, and upstream base must use the same SHA"
)

print("Rendered Anvil daemon and GC use anvil-nix-shared; controller, profile, and runtime sandbox images share one immutable SHA.")
