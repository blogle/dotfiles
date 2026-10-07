#!/usr/bin/env python3
"""Validate production-only Anvil storage overrides in the rendered manifest."""

import subprocess

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

print("Rendered Anvil daemon and GC both use anvil-nix-shared.")
