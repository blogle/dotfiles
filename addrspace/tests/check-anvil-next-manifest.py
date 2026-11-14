#!/usr/bin/env python3
"""Validate isolation and runtime wiring for the Anvil Next overlay."""

import hashlib
import re
import subprocess
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
OVERLAY = ROOT / "addrspace/apps/anvil-next"


def render(path):
    output = subprocess.check_output(
        ["kubectl", "kustomize", str(path)], cwd=ROOT, text=True
    )
    return [resource for resource in yaml.safe_load_all(output) if resource]


def index(resources):
    return {
        (resource["kind"], resource["metadata"]["name"]): resource
        for resource in resources
    }


overlay_objects = render(OVERLAY)
selected = index(overlay_objects)
incumbent = render(ROOT / "addrspace/apps/anvil")

# All objects in this independently registered overlay belong to dotfiles,
# except its one explicitly cluster-scoped Namespace object.
namespaces = [resource for resource in overlay_objects if resource["kind"] == "Namespace"]
assert len(namespaces) == 1, "overlay must render exactly one Namespace"
assert namespaces[0]["metadata"]["name"] == "dotfiles", "overlay Namespace must be dotfiles"
assert "namespace" not in namespaces[0]["metadata"], "Namespace must stay cluster-scoped"
for resource in overlay_objects:
    kind = resource["kind"]
    metadata = resource["metadata"]
    assert kind != "Secret", "overlay must not render plaintext Secret resources"
    if kind != "Namespace":
        assert metadata.get("namespace") == "dotfiles", (
            "every non-Namespace overlay object must be in the dotfiles namespace"
        )

# Preserve the upstream base pin and keep every deployed image on that exact SHA.
kustomization = yaml.safe_load((OVERLAY / "kustomization.yaml").read_text())
base_match = re.fullmatch(
    r"github\.com/blogle/anvil//k8s/base\?ref=([0-9a-f]{40})",
    kustomization["resources"][0],
)
assert base_match, "dotfiles base must pin a full immutable commit SHA"
base_sha = base_match.group(1)
images = {image["name"]: image["newTag"] for image in kustomization["images"]}
expected_images = {
    "ghcr.io/blogle/anvil",
    "ghcr.io/blogle/anvil-sandbox",
    "ghcr.io/blogle/anvil-nix-daemon",
}
assert set(images) == expected_images, "dotfiles overlay must pin exactly the three Anvil images"
assert all(tag == f"sha-{base_sha}" for tag in images.values()), (
    "all dotfiles image tags must match the pinned base SHA"
)

runtime = selected[("ConfigMap", "anvil-runtime")]["data"]
profile = selected[("Deployment", "anvil-profile")]
profile_image = profile["spec"]["template"]["spec"]["containers"][0]["image"]
assert profile_image == f"ghcr.io/blogle/anvil-sandbox:sha-{base_sha}", (
    "profile sandbox image must use the pinned base SHA"
)
assert runtime["ANVIL_SANDBOX_IMAGE"] == profile_image, (
    "runtime sandbox image must match the rendered profile image"
)
assert runtime["ANVIL_NAMESPACE"] == "dotfiles", "SealedSecret-bound namespace must remain dotfiles"
assert runtime["ANVIL_PREVIEW_DOMAIN"] == "next.preview.thejeffer.net"
assert runtime["BASE_DOMAIN"] == "next.preview.thejeffer.net"
assert runtime["ANVIL_ANNOTATION_PREFIX"] == "anvil-next.thejeffer.net"

nexus_toml = yaml.safe_load(
    (ROOT / "addrspace/apps/nexus/configmap.yaml").read_text()
)["data"]["nexus.toml"]
nexus_deployment = yaml.safe_load(
    (ROOT / "addrspace/apps/nexus/deployment.yaml").read_text()
)
nexus_annotations = nexus_deployment["spec"]["template"]["metadata"]["annotations"]
assert "[mcp.servers.anvil_next]" in nexus_toml
assert "[mcp.servers.anvil_dotfiles]" not in nexus_toml
assert "url = \"http://anvil-mcp.dotfiles.svc.cluster.local:8081/mcp\"" in nexus_toml
assert "[mcp.servers.anvil]" in nexus_toml
assert "url = \"http://anvil-mcp.anvil.svc.cluster.local:8081/mcp\"" in nexus_toml
assert nexus_annotations["checksum/config"] == hashlib.sha256(nexus_toml.encode()).hexdigest()
assert nexus_annotations["anvil-next.example.invalid/mcp-contract-revision"] == base_sha
assert "anvil-dotfiles.example.invalid/mcp-contract-revision" not in nexus_annotations

# SealedSecret metadata and key names are safe to inspect; never print or
# include encryptedData values in diagnostics.
sealed_names = {
    "anvil-profile-credentials": {"ANVIL_OPENCODE_SERVER_PASSWORD"},
    "anvil-controller-signing": {"ANVIL_SESSION_SIGNING_SECRET"},
    "github-app-credentials-dotfiles": {
        "ANVIL_GITHUB_APP_ID",
        "ANVIL_GITHUB_INSTALLATION_ID",
        "ANVIL_GITHUB_PRIVATE_KEY",
    },
}
sealed = {name: resource for (kind, name), resource in selected.items() if kind == "SealedSecret"}
assert set(sealed) == set(sealed_names), "overlay must contain exactly its three expected SealedSecrets"
for name, expected_keys in sealed_names.items():
    resource = sealed[name]
    metadata = resource["metadata"]
    spec = resource["spec"]
    template_metadata = spec["template"]["metadata"]
    assert metadata.get("name") == name, "SealedSecret metadata name mismatch"
    assert metadata.get("namespace") == "dotfiles", "SealedSecret must be scoped to dotfiles"
    assert spec.get("encryptedData", {}).keys() == expected_keys, (
        "SealedSecret encrypted key-name set mismatch"
    )
    assert template_metadata.get("name") == name, "SealedSecret template name mismatch"
    assert template_metadata.get("namespace") == "dotfiles", (
        "SealedSecret template must be scoped to dotfiles"
    )
    assert spec["template"].get("type", "") in ("", "Opaque"), (
        "SealedSecret template must create an ordinary Opaque Secret"
    )

# anvild must require all three namespace-specific credential sources.
anvild = selected[("Deployment", "anvild")]
container = anvild["spec"]["template"]["spec"]["containers"][0]
env_from = container.get("envFrom", [])
required_secret_refs = {
    "github-app-credentials-dotfiles",
    "anvil-profile-credentials",
    "anvil-controller-signing",
}
actual_secret_refs = {
    item["secretRef"]["name"]
    for item in env_from
    if "secretRef" in item and item["secretRef"].get("optional") is False
}
assert required_secret_refs <= actual_secret_refs, (
    "anvild envFrom must require the dotfiles App, profile, and signing Secrets"
)
password_env = [
    item
    for item in profile["spec"]["template"]["spec"]["containers"][0].get("env", [])
    if item.get("name") == "ANVIL_OPENCODE_SERVER_PASSWORD"
]
assert len(password_env) == 1, "profile must define its password exactly once"
password_ref = password_env[0]["valueFrom"]["secretKeyRef"]
assert password_ref == {
    "name": "anvil-profile-credentials",
    "key": "ANVIL_OPENCODE_SERVER_PASSWORD",
}, "profile password must come from the dotfiles profile Secret"

# Pod-template annotations make namespace-owned runtime configuration changes
# trigger a rollout. Check all configured annotation values without dumping them.
annotations = anvild["spec"]["template"]["metadata"].get("annotations", {})
for key, suffix in {
    "ANVIL_PREVIEW_DOMAIN": "preview-domain",
    "ANVIL_ANNOTATION_PREFIX": "annotation-prefix",
    "ANVIL_GIT_COMMITTER_NAME": "git-committer-name",
    "ANVIL_GIT_COMMITTER_EMAIL": "git-committer-email",
    "BASE_DOMAIN": "base-domain",
    "AGENT_SANDBOX_ROUTER_URL": "sandbox-router-url",
    "ANVIL_SANDBOX_IMAGE": "sandbox-image",
}.items():
    annotation = f"anvil-next.thejeffer.net/runtime-config-{suffix}"
    assert annotations.get(annotation) == runtime[key], (
        "dotfiles anvild rollout annotation must match its runtime ConfigMap value"
    )

# Preserve stable Ingress and Certificate identities because Flux pruning is off.
ingress = selected[("Ingress", "anvil-dotfiles")]
certificate = selected[("Certificate", "anvil-dotfiles-preview-tls")]
assert ingress["metadata"]["name"] == "anvil-dotfiles"
assert certificate["metadata"]["name"] == "anvil-dotfiles-preview-tls"
assert {rule["host"] for rule in ingress["spec"]["rules"]} == {
    "anvil-next.thejeffer.net",
    "*.next.preview.thejeffer.net",
}, "Ingress must expose only the canonical Anvil Next hosts"
assert ingress["spec"]["tls"][0]["secretName"] == "anvil-dotfiles-preview-tls"
assert set(certificate["spec"]["dnsNames"]) == {
    "anvil-next.thejeffer.net",
    "*.next.preview.thejeffer.net",
}, "Certificate must cover only the canonical Anvil Next hosts"
assert certificate["spec"]["secretName"] == "anvil-dotfiles-preview-tls"

# No namespaced objects, storage claims, sealed/plain Secret names, or ingress
# hosts may collide with the incumbent Anvil instance.
incumbent_index = index(incumbent)
assert ("Namespace", "dotfiles") not in incumbent_index, "dotfiles Namespace collides with incumbent"
incumbent_pvcs = {
    (resource["metadata"].get("namespace"), resource["metadata"]["name"])
    for resource in incumbent
    if resource["kind"] == "PersistentVolumeClaim"
}
dotfiles_pvcs = {
    (resource["metadata"].get("namespace"), resource["metadata"]["name"])
    for resource in overlay_objects
    if resource["kind"] == "PersistentVolumeClaim"
}
assert not (incumbent_pvcs & dotfiles_pvcs), "dotfiles PVC identities must not collide with incumbent PVCs"
incumbent_secret_names = {
    (resource["metadata"].get("namespace"), resource["metadata"]["name"])
    for resource in incumbent
    if resource["kind"] in {"Secret", "SealedSecret"}
}
dotfiles_secret_names = {
    (resource["metadata"].get("namespace"), resource["metadata"]["name"])
    for resource in overlay_objects
    if resource["kind"] in {"Secret", "SealedSecret"}
}
assert not (incumbent_secret_names & dotfiles_secret_names), (
    "dotfiles Secret identities must not collide with incumbent Secret identities"
)
incumbent_hosts = {
    rule["host"]
    for resource in incumbent
    if resource["kind"] == "Ingress"
    for rule in resource.get("spec", {}).get("rules", [])
}
dotfiles_hosts = {
    rule["host"]
    for resource in overlay_objects
    if resource["kind"] == "Ingress"
    for rule in resource.get("spec", {}).get("rules", [])
}
assert dotfiles_hosts and not (incumbent_hosts & dotfiles_hosts), (
    "dotfiles ingress hosts must be distinct from incumbent Anvil hosts"
)

print("Anvil Next overlay isolation and runtime invariants passed.")
