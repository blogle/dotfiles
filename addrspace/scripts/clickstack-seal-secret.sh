#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage:
  bash addrspace/scripts/clickstack-seal-secret.sh values
  bash addrspace/scripts/clickstack-seal-secret.sh mcp

values creates random ClickStack chart credentials and seals values.yaml as
clickstack-values in kube-system. mcp interactively seals a Personal API Access
Key as clickstack-mcp-credentials in nexus and stages Nexus's MCP URL, required
Secret reference, checksum, and Kustomization entry in the same follow-up. No
plaintext credential is written to the repository; only SealedSecret
ciphertext is added. Temporary plaintext is kept in a mode-0700 directory and
deleted on exit.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

add_resource() {
  local kustomization=$1 resource=$2
  python3 - "$ROOT/$kustomization" "$resource" <<'PY'
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

path = Path(sys.argv[1])
resource = sys.argv[2]
text = path.read_text()
resource_line = re.compile(r"^\s+-\s+" + re.escape(resource) + r"\s*(?:#.*)?$")
if any(resource_line.match(line) for line in text.splitlines()):
    raise SystemExit(0)

lines = text.splitlines(keepends=True)
header = next((i for i, line in enumerate(lines) if re.match(r"^resources:\s*(?:#.*)?\s*$", line.rstrip("\r\n"))), None)
if header is None:
    raise SystemExit(f"{path} has no top-level resources: list")

lines.insert(header + 1, f"  - {resource}\n")
fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
try:
    os.fchmod(fd, stat.S_IMODE(path.stat().st_mode))
    with os.fdopen(fd, "w") as stream:
        stream.writelines(lines)
    os.replace(temporary, path)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
}

prepare_mcp_wiring() {
  local temporary_dir=$1 resource=$2
  python3 - "$ROOT" "$temporary_dir" "$resource" <<'PY'
import hashlib
from pathlib import Path
import re
import sys
import yaml

root = Path(sys.argv[1])
temporary_dir = Path(sys.argv[2])
resource = sys.argv[3]
configmap_path = root / "addrspace/apps/nexus/configmap.yaml"
deployment_path = root / "addrspace/apps/nexus/deployment.yaml"
kustomization_path = root / "addrspace/apps/nexus/kustomization.yaml"
configmap = configmap_path.read_text()
deployment = deployment_path.read_text()
kustomization = kustomization_path.read_text()

if "[mcp.servers.clickstack]" in configmap or "CLICKSTACK_MCP_API_KEY" in deployment:
    raise SystemExit("Nexus ClickStack MCP wiring is already present; refusing duplicate enablement")

toml_anchor = '''    [mcp.servers.kubernetes]
    protocol = "streamable-http"
    url = "http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:8080/mcp"

    [llm]
'''
toml_replacement = '''    [mcp.servers.kubernetes]
    protocol = "streamable-http"
    url = "http://kubernetes-mcp.kubernetes-mcp.svc.cluster.local:8080/mcp"

    [mcp.servers.clickstack]
    protocol = "streamable-http"
    url = "http://clickstack-app.observability.svc.cluster.local:3000/api/mcp"
    auth.token = "{{ env.CLICKSTACK_MCP_API_KEY }}"

    [llm]
'''
if configmap.count(toml_anchor) != 1:
    raise SystemExit("Nexus TOML anchor changed; inspect and wire ClickStack MCP manually")
configmap = configmap.replace(toml_anchor, toml_replacement, 1)

env_anchor = '''            - name: LIFIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: nexus-lific-credentials
                  key: LIFIC_API_KEY
'''
env_replacement = env_anchor + '''            - name: CLICKSTACK_MCP_API_KEY
              valueFrom:
                secretKeyRef:
                  name: clickstack-mcp-credentials
                  key: api-key
                  optional: false
'''
if deployment.count(env_anchor) != 1:
    raise SystemExit("Nexus Deployment env anchor changed; inspect and wire ClickStack MCP manually")
deployment = deployment.replace(env_anchor, env_replacement, 1)

config = yaml.safe_load(configmap)["data"]["nexus.toml"]
checksum = hashlib.sha256(config.encode()).hexdigest()
deployment, checksum_count = re.subn(
    r"(?m)^(        checksum/config: )[0-9a-f]{64}$",
    lambda match: match.group(1) + checksum,
    deployment,
)
if checksum_count != 1:
    raise SystemExit("Could not refresh Nexus checksum/config")

resource_pattern = re.compile(r"^\s+-\s+" + re.escape(resource) + r"\s*(?:#.*)?$")
if any(resource_pattern.match(line) for line in kustomization.splitlines()):
    raise SystemExit("MCP SealedSecret is already listed in Nexus Kustomization")
lines = kustomization.splitlines(keepends=True)
header = next((i for i, line in enumerate(lines) if re.match(r"^resources:\s*(?:#.*)?\s*$", line.rstrip("\r\n"))), None)
if header is None:
    raise SystemExit("Nexus Kustomization has no top-level resources: list")
lines.insert(header + 1, f"  - {resource}\n")
kustomization = "".join(lines)

(temporary_dir / "nexus-configmap.yaml").write_text(configmap)
(temporary_dir / "nexus-deployment.yaml").write_text(deployment)
(temporary_dir / "nexus-kustomization.yaml").write_text(kustomization)
PY
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
mode=$1
case "$mode" in
  values)
    secret_name=clickstack-values
    secret_namespace=kube-system
    secret_key=values.yaml
    default_output=addrspace/platform/observability/clickstack-values.sealed.yaml
    ;;
  mcp)
    secret_name=clickstack-mcp-credentials
    secret_namespace=nexus
    secret_key=api-key
    default_output=addrspace/apps/nexus/clickstack-mcp-credentials.sealed.yaml
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *) usage >&2; exit 2 ;;
esac

output="$ROOT/$default_output"
[[ ! -e "$output" ]] || fail "refusing to overwrite existing output: $output"
[[ -d "$(dirname -- "$output")" ]] || fail "output directory does not exist: $(dirname -- "$output")"

for tool in kubectl kubeseal openssl python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required; run this script through nix develop"
done

context=$(kubectl config current-context 2>/dev/null) || fail "no kubectl context; configure the target cluster first"
[[ -n "$context" ]] || fail "no kubectl context; configure the target cluster first"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/clickstack-seal.XXXXXX")
trap 'rm -rf -- "$tmpdir"' EXIT HUP INT TERM
cert="$tmpdir/sealed-secrets.pem"
if ! kubeseal \
  --fetch-cert \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  > "$cert"; then
  fail "could not fetch the Sealed Secrets public certificate from context $context"
fi
[[ -s "$cert" ]] || fail "Sealed Secrets returned an empty public certificate"

case "$mode" in
  values)
    hyperdx_api_key=$(python3 -c 'import uuid; print(uuid.uuid4())')
    clickhouse_password=$(openssl rand -hex 32)
    clickhouse_app_password=$(openssl rand -hex 32)
    mongodb_password=$(openssl rand -hex 32)
    printf 'hyperdx:\n  secrets:\n    HYPERDX_API_KEY: "%s"\n    CLICKHOUSE_PASSWORD: "%s"\n    CLICKHOUSE_APP_PASSWORD: "%s"\n    MONGODB_PASSWORD: "%s"\n' \
      "$hyperdx_api_key" "$clickhouse_password" "$clickhouse_app_password" "$mongodb_password" \
      > "$tmpdir/values.yaml"
    unset hyperdx_api_key clickhouse_password clickhouse_app_password mongodb_password
    input_file="$tmpdir/values.yaml"
    ;;
  mcp)
    [[ -t 0 ]] || fail "MCP key input must be interactive; refusing to read it from a pipe or file"
    read -r -s -p 'Paste the ClickStack Personal API Access Key: ' mcp_api_key
    printf '\n' >&2
    [[ -n "$mcp_api_key" ]] || fail "the Personal API Access Key cannot be empty"
    printf '%s' "$mcp_api_key" > "$tmpdir/api-key"
    unset mcp_api_key
    input_file="$tmpdir/api-key"
    ;;
esac

sealed="$tmpdir/sealed-secret.yaml"
if ! kubectl create secret generic "$secret_name" \
  --namespace "$secret_namespace" \
  --from-file="$secret_key=$input_file" \
  --dry-run=client -o yaml \
  | kubeseal --cert "$cert" --scope strict --format yaml > "$sealed"; then
  fail "failed to seal $secret_name; no plaintext output was written"
fi
[[ -s "$sealed" ]] || fail "kubeseal produced no output"
if grep -Eq '^([[:space:]]*)(stringData|data):' "$sealed"; then
  fail "kubeseal output unexpectedly contains plaintext Secret data"
fi
if [[ "$mode" == mcp ]]; then
  if ! prepare_mcp_wiring "$tmpdir" "$(basename -- "$output")"; then
    fail "could not prepare the Nexus MCP follow-up; repository files were not changed"
  fi
fi
install -m 0644 -- "$sealed" "$output"
case "$mode" in
  values)
    if ! add_resource addrspace/platform/observability/kustomization.yaml "$(basename -- "$output")"; then
      rm -f -- "$output"
      fail "could not register the sealed values manifest in the observability Kustomization"
    fi
    ;;
  mcp)
    install -m 0644 -- "$tmpdir/nexus-configmap.yaml" addrspace/apps/nexus/configmap.yaml
    install -m 0644 -- "$tmpdir/nexus-deployment.yaml" addrspace/apps/nexus/deployment.yaml
    install -m 0644 -- "$tmpdir/nexus-kustomization.yaml" addrspace/apps/nexus/kustomization.yaml
    ;;
esac
printf 'Wrote encrypted SealedSecret: %s\n' "$output"
case "$mode" in
  values)
    printf 'Registered the encrypted values manifest in addrspace/platform/observability/kustomization.yaml.\n'
    ;;
  mcp)
    printf 'Enabled Nexus ClickStack MCP with the required key reference and refreshed checksum. Review and commit the sealed key plus Nexus changes together.\n'
    ;;
esac
