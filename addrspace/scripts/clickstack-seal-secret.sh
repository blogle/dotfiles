#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage:
  bash addrspace/scripts/clickstack-seal-secret.sh values [output-file]
  bash addrspace/scripts/clickstack-seal-secret.sh mcp [output-file]

values creates random ClickStack chart credentials and seals values.yaml as
clickstack-values in kube-system. mcp interactively seals a Personal API Access
Key as clickstack-mcp-credentials in nexus. Only SealedSecret ciphertext is
written to the repository; temporary plaintext is kept in a mode-0700 directory
and deleted on exit.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 2; }
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

output=${2:-$default_output}
case "$output" in
  /*) ;;
  *) output="$ROOT/$output" ;;
esac
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
install -m 0644 -- "$sealed" "$output"
printf 'Wrote encrypted SealedSecret: %s\n' "$output"
case "$mode" in
  values)
    printf 'Add clickstack-values.sealed.yaml to addrspace/platform/observability/kustomization.yaml resources.\n'
    ;;
  mcp)
    printf 'Add clickstack-mcp-credentials.sealed.yaml to addrspace/apps/nexus/kustomization.yaml resources.\n'
    ;;
esac
