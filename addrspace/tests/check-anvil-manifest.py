#!/usr/bin/env python3
"""Validate production Anvil storage and immutable image parity."""

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import yaml


def nix_claim(resource):
    if resource["kind"] == "Deployment":
        pod_spec = resource["spec"]["template"]["spec"]
    else:
        pod_spec = resource["spec"]["jobTemplate"]["spec"]["template"]["spec"]
    volumes = {volume["name"]: volume for volume in pod_spec.get("volumes", [])}
    return volumes["nix"]["persistentVolumeClaim"]["claimName"]


def render(path):
    rendered = subprocess.check_output(["kubectl", "kustomize", str(path)], text=True)
    resources = [resource for resource in yaml.safe_load_all(rendered) if resource]
    return {(resource["kind"], resource["metadata"]["name"]): resource for resource in resources}


selected = render("addrspace/apps/anvil")

for key in (("Deployment", "anvil-nix-daemon"), ("CronJob", "anvil-nix-gc")):
    assert nix_claim(selected[key]) == "anvil-nix-shared", f"{key} must use anvil-nix-shared"

controller_image = selected[("Deployment", "anvild")]["spec"]["template"]["spec"]["containers"][0]["image"]
profile_image = selected[("Deployment", "anvil-profile")]["spec"]["template"]["spec"]["containers"][0]["image"]
sandbox_image = selected[("ConfigMap", "anvil-runtime")]["data"]["ANVIL_SANDBOX_IMAGE"]
controller = selected[("Deployment", "anvild")]
controller_template = controller["spec"]["template"]
controller_annotations = controller_template["metadata"]["annotations"]
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

critical_runtime_keys = {
    "ANVIL_PREVIEW_DOMAIN": "preview-domain",
    "ANVIL_ANNOTATION_PREFIX": "annotation-prefix",
    "ANVIL_GIT_COMMITTER_NAME": "git-committer-name",
    "ANVIL_GIT_COMMITTER_EMAIL": "git-committer-email",
    "ANVIL_CONCURRENCY": "concurrency",
    "BASE_DOMAIN": "base-domain",
    "AGENT_SANDBOX_ROUTER_URL": "sandbox-router-url",
    "ANVIL_SANDBOX_IMAGE": "sandbox-image",
}
runtime_data = selected[("ConfigMap", "anvil-runtime")]["data"]
for key, annotation_suffix in critical_runtime_keys.items():
    annotation_key = f"anvil.thejeffer.net/runtime-config-{annotation_suffix}"
    assert controller_annotations[annotation_key] == runtime_data[key], (
        f"anvild template annotation must track anvil-runtime.data.{key}"
    )

# Simulate the sandbox image source changing (as an upstream Renovate bump does).
# The rendered ConfigMap and controller pod template must both change without a
# separately maintained revision token.
with tempfile.TemporaryDirectory(prefix="anvil-kustomize-test-") as temporary_directory:
    simulated_overlay = Path(temporary_directory) / "anvil"
    shutil.copytree("addrspace/apps/anvil", simulated_overlay)
    simulated_kustomization_path = simulated_overlay / "kustomization.yaml"
    simulated_kustomization = yaml.safe_load(simulated_kustomization_path.read_text())
    simulated_sha = "a" * 40
    for image in simulated_kustomization["images"]:
        if image["name"] == "ghcr.io/blogle/anvil-sandbox":
            image["newTag"] = f"sha-{simulated_sha}"
            break
    else:
        raise AssertionError("Anvil sandbox image transform is missing")
    simulated_kustomization_path.write_text(yaml.safe_dump(simulated_kustomization, sort_keys=False))
    simulated = render(simulated_overlay)

simulated_runtime_image = simulated[("ConfigMap", "anvil-runtime")]["data"]["ANVIL_SANDBOX_IMAGE"]
simulated_annotations = simulated[("Deployment", "anvild")]["spec"]["template"]["metadata"]["annotations"]
sandbox_annotation = "anvil.thejeffer.net/runtime-config-sandbox-image"
assert simulated_runtime_image.endswith(f"sha-{simulated_sha}")
assert simulated_annotations[sandbox_annotation] == simulated_runtime_image
assert simulated_annotations[sandbox_annotation] != controller_annotations[sandbox_annotation], (
    "sandbox image ConfigMap changes must change the anvild pod template"
)

print("Rendered Anvil storage and image parity pass; critical runtime ConfigMap values stamp the anvild pod template, including sandbox-image changes.")
