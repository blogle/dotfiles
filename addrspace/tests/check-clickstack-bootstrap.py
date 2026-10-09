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
    clickstack_values = yaml.safe_load(
        (ROOT / "addrspace/platform/observability/clickstack/helmchart.yaml").read_text()
    )["spec"]["valuesContent"]
    clickstack = yaml.safe_load(clickstack_values)["clickhouse"]
    assert clickstack["cluster"]["spec"]["containerTemplate"]["image"]["tag"] == "25.7-alpine"
    keeper = clickstack["keeper"]["spec"]
    assert keeper["containerTemplate"]["image"]["tag"] == "25.7-alpine"
    assert keeper["containerTemplate"]["env"] == [
        {"name": "CLICKHOUSE_CONFIG", "value": "/etc/clickhouse-keeper/config.yaml"}
    ]
    assert keeper["settings"]["extraConfig"] == {
        "tmp_path": "/var/lib/clickhouse/tmp/",
        "user_files_path": "/var/lib/clickhouse/user_files/",
        "format_schema_path": "/var/lib/clickhouse/format_schemas/",
        "user_directories": {
            "users_xml": {"path": "/etc/clickhouse-server/users.xml"},
        },
    }
    assert "clickstack-values" in helper and "secret_namespace=kube-system" in helper
    assert "CLICKHOUSE_PASSWORD" in helper and "CLICKHOUSE_APP_PASSWORD" in helper
    assert "MONGODB_PASSWORD" in helper and "HYPERDX_API_KEY" in helper
    assert "--fetch-cert" in helper and "--scope strict" in helper
    active_toml = yaml.safe_load((ROOT / "addrspace/apps/nexus/configmap.yaml").read_text())["data"]["nexus.toml"]
    active_nexus = yaml.safe_load((ROOT / "addrspace/apps/nexus/deployment.yaml").read_text())
    active_kustomization = yaml.safe_load((ROOT / "addrspace/apps/nexus/kustomization.yaml").read_text())
    token_envs = [
        env
        for env in active_nexus["spec"]["template"]["spec"]["containers"][0]["env"]
        if env["name"] == "CLICKSTACK_MCP_API_KEY"
    ]
    mcp_enabled = "[mcp.servers.clickstack]" in active_toml
    current_checksum = hashlib.sha256(active_toml.encode()).hexdigest()
    assert active_nexus["spec"]["template"]["metadata"]["annotations"]["checksum/config"] == current_checksum
    if mcp_enabled:
        assert len(token_envs) == 1
        assert token_envs[0]["valueFrom"]["secretKeyRef"] == {
            "name": "clickstack-mcp-credentials",
            "key": "api-key",
            "optional": False,
        }
        sealed = yaml.safe_load(
            (ROOT / "addrspace/apps/nexus/clickstack-mcp-credentials.sealed.yaml").read_text()
        )
        assert sealed["metadata"] == {"name": "clickstack-mcp-credentials", "namespace": "nexus"}
        assert set(sealed["spec"]["encryptedData"]) == {"api-key"}
        assert "clickstack-mcp-credentials.sealed.yaml" in active_kustomization["resources"]
    else:
        assert not token_envs

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

        if mcp_enabled:
            result = subprocess.run(
                [sys.executable, "-", str(root), str(root / "tmp"), "clickstack-mcp-credentials.sealed.yaml"],
                input=prepare_mcp,
                text=True,
                capture_output=True,
            )
            assert result.returncode != 0 and "already present" in result.stderr
        else:
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
