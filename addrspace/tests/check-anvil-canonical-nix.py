#!/usr/bin/env python3
"""Assert production consumes Anvil's one canonical shared Nix PVC/daemon/GC."""
from pathlib import Path
import subprocess
import yaml

root = Path(__file__).resolve().parents[2]
overlay = yaml.safe_load((root / "addrspace/apps/anvil/kustomization.yaml").read_text())
resource_names = overlay["resources"]
assert not any(name.endswith("nix-shared-pvc.yaml") for name in resource_names), "dotfiles must not redeclare Anvil's PVC"
patches = [patch["path"] for patch in overlay["patches"] if "path" in patch]
assert "nix-shared-pvc.patch.yaml" in patches, "missing cluster-only PVC customization"
assert "nix-daemon.patch.yaml" not in patches, "daemon volume wiring is upstream-owned"
assert "nix-gc.patch.yaml" not in patches, "GC volume wiring is upstream-owned"

rendered = subprocess.check_output(["kubectl", "kustomize", "addrspace/apps/anvil"], cwd=root, text=True)
objects = [item for item in yaml.safe_load_all(rendered) if item]
selected = {(item["kind"], item["metadata"]["name"]): item for item in objects}

claims = [obj for obj in objects if obj["kind"] == "PersistentVolumeClaim"]
nix_claims = [obj for obj in claims if obj["metadata"]["name"].startswith("anvil-nix")]
assert len(nix_claims) == 1, f"expected exactly one Anvil Nix PVC, got {[x['metadata']['name'] for x in nix_claims]}"
pvc = nix_claims[0]
assert pvc["metadata"]["name"] == "anvil-nix-shared"
assert pvc["spec"]["storageClassName"] == "openebs-zfspv-shared-ext4"
assert pvc["spec"]["resources"]["requests"]["storage"] == "100Gi"
assert pvc["spec"]["accessModes"] == ["ReadWriteOnce"]

daemon = selected[("Deployment", "anvil-nix-daemon")]
gc = selected[("CronJob", "anvil-nix-gc")]
def volume_claim(spec):
    matches = [item for item in spec["volumes"] if item["name"] == "nix"]
    assert len(matches) == 1
    return matches[0]["persistentVolumeClaim"]["claimName"]

assert volume_claim(daemon["spec"]["template"]["spec"]) == "anvil-nix-shared"
assert volume_claim(gc["spec"]["jobTemplate"]["spec"]["template"]["spec"]) == "anvil-nix-shared"
assert selected[("ConfigMap", "anvil-runtime")]["data"]["ANVIL_NIX_PVC"] == "anvil-nix-shared"
print("Anvil production overlay: one upstream PVC, shared daemon and GC consumers, unchanged OpenEBS class and capacity.")
