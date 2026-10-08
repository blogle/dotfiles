#!/usr/bin/env python3
"""Exercise the credential helper's Kustomize and Nexus opt-in edits offline."""

import ast
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

import yaml


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "addrspace/scripts/clickstack-seal-secret.sh"


def helper_python_blocks():
    text = HELPER.read_text()
    blocks = re.findall(r"python3 - .*?<<'PY'\n(.*?)\nPY", text, re.DOTALL)
    assert len(blocks) == 2, f"Expected two embedded Python helpers, found {len(blocks)}"
    for block in blocks:
        ast.parse(block)
    return blocks


def run_embedded(block, *args):
    subprocess.run(
        [sys.executable, "-", *(str(arg) for arg in args)],
        input=block,
        text=True,
        check=True,
    )


def main():
    add_resource, prepare_mcp = helper_python_blocks()
    helper = HELPER.read_text()
    assert "clickstack-values" in helper and "secret_namespace=kube-system" in helper
    assert "CLICKHOUSE_PASSWORD" in helper and "CLICKHOUSE_APP_PASSWORD" in helper
    assert "MONGODB_PASSWORD" in helper and "HYPERDX_API_KEY" in helper
    assert "--fetch-cert" in helper and "--scope strict" in helper
    active_toml = yaml.safe_load((ROOT / "addrspace/apps/nexus/configmap.yaml").read_text())["data"]["nexus.toml"]
    active_nexus = yaml.safe_load((ROOT / "addrspace/apps/nexus/deployment.yaml").read_text())
    assert "[mcp.servers.clickstack]" not in active_toml
    assert all(
        env["name"] != "CLICKSTACK_MCP_API_KEY"
        for env in active_nexus["spec"]["template"]["spec"]["containers"][0]["env"]
    )
    current_checksum = hashlib.sha256(active_toml.encode()).hexdigest()
    assert active_nexus["spec"]["template"]["metadata"]["annotations"]["checksum/config"] == current_checksum

    with tempfile.TemporaryDirectory(prefix="clickstack-bootstrap-test-") as temp:
        root = Path(temp)
        app = root / "addrspace/apps/nexus"
        obs = root / "addrspace/platform/observability"
        app.mkdir(parents=True)
        obs.mkdir(parents=True)
        (root / "tmp").mkdir()
        for name in ("configmap.yaml", "deployment.yaml", "kustomization.yaml"):
            shutil.copy(ROOT / "addrspace/apps/nexus" / name, app / name)
        shutil.copy(ROOT / "addrspace/platform/observability/kustomization.yaml", obs / "kustomization.yaml")

        run_embedded(prepare_mcp, root, root / "tmp", "clickstack-mcp-credentials.sealed.yaml")
        configmap = yaml.safe_load((root / "tmp/nexus-configmap.yaml").read_text())
        deployment = yaml.safe_load((root / "tmp/nexus-deployment.yaml").read_text())
        kustomization = yaml.safe_load((root / "tmp/nexus-kustomization.yaml").read_text())
        toml = configmap["data"]["nexus.toml"]
        assert "[mcp.servers.clickstack]" in toml
        assert "http://clickstack-app.observability.svc.cluster.local:3000/api/mcp" in toml
        assert 'auth.token = "{{ env.CLICKSTACK_MCP_API_KEY }}"' in toml
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        token_env = next(env for env in container["env"] if env["name"] == "CLICKSTACK_MCP_API_KEY")
        assert token_env["valueFrom"]["secretKeyRef"] == {
            "name": "clickstack-mcp-credentials",
            "key": "api-key",
            "optional": False,
        }
        expected_checksum = hashlib.sha256(toml.encode()).hexdigest()
        assert deployment["spec"]["template"]["metadata"]["annotations"]["checksum/config"] == expected_checksum
        assert "clickstack-mcp-credentials.sealed.yaml" in kustomization["resources"]

        run_embedded(add_resource, obs / "kustomization.yaml", "clickstack-values.sealed.yaml")
        obs_kustomization = yaml.safe_load((obs / "kustomization.yaml").read_text())
        assert "clickstack-values.sealed.yaml" in obs_kustomization["resources"]

    print("ClickStack secret resource insertion and post-bootstrap Nexus MCP wiring passed.")


if __name__ == "__main__":
    main()
