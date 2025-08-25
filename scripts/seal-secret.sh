#!/usr/bin/env bash
set -euo pipefail

# Generic helper to generate SealedSecret manifest(s).
# - Supports multiple namespaces
# - Supports literals and files
# - Default scope is cluster-wide (portable across namespaces). Use --scope strict to bind to ns+name.
#
# Examples:
#   # One secret in one namespace from a literal
#   ./scripts/seal-secret.sh --name cloudflare -n cert-manager \
#     --literal api-key=YOUR_KEY \
#     --output-dir hosts/nandstorm/k8s/infrastructure
#
#   # Same secret for two namespaces (cert-manager, external-dns)
#   ./scripts/seal-secret.sh --name cloudflare -n cert-manager -n external-dns \
#     --literal api-key=YOUR_KEY \
#     --output-dir hosts/nandstorm/k8s/infrastructure --scope cluster-wide
#
#   # Mix literals and files
#   ./scripts/seal-secret.sh --name app-creds -n myns \
#     --literal username=alice \
#     --file password=./secrets/password.txt \
#     --output-dir hosts/nandstorm/k8s/apps/myns

NAME=""
NAMESPACES=()
LITERALS=()
FILES=()
OUT_DIR="."
SCOPE="cluster-wide"           # strict|namespace-wide|cluster-wide
CTRL_NS="kube-system"
CTRL_NAME="sealed-secrets-controller"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --name NAME -n NS [ -n NS2 ... ] [--literal k=v ...] [--file k=path ...]
          [--output-dir DIR] [--scope strict|namespace-wide|cluster-wide]
          [--controller-namespace NS] [--controller-name NAME] [--dry-run]

Generates one SealedSecret manifest per namespace as: <output-dir>/<name>-<namespace>.sealed.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    -n|--namespace) NAMESPACES+=("$2"); shift 2 ;;
    --literal) LITERALS+=("$2"); shift 2 ;;
    --file) FILES+=("$2"); shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --controller-namespace) CTRL_NS="$2"; shift 2 ;;
    --controller-name) CTRL_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$NAME" || ${#NAMESPACES[@]} -eq 0 ]]; then
  echo "Error: --name and at least one --namespace are required" >&2
  usage; exit 1
fi

if [[ ${#LITERALS[@]} -eq 0 && ${#FILES[@]} -eq 0 ]]; then
  echo "Error: provide at least one --literal or --file" >&2
  usage; exit 1
fi

mkdir -p "$OUT_DIR"

mk_secret_yaml() {
  local ns="$1"
  echo "apiVersion: v1"
  echo "kind: Secret"
  echo "metadata:"
  echo "  name: $NAME"
  echo "  namespace: $ns"
  echo "type: Opaque"

  if [[ ${#LITERALS[@]} -gt 0 ]]; then
    echo "stringData:"
    for kv in "${LITERALS[@]}"; do
      key="${kv%%=*}"; val="${kv#*=}"
      # naive YAML escaping for common cases
      printf "  %s: \"%s\"\n" "$key" "$val"
    done
  fi

  if [[ ${#FILES[@]} -gt 0 ]]; then
    echo "data:"
    for kv in "${FILES[@]}"; do
      key="${kv%%=*}"; path="${kv#*=}"
      if [[ ! -f "$path" ]]; then
        echo "Error: file not found: $path" >&2; exit 1
      fi
      b64=$(base64 -w0 < "$path")
      printf "  %s: %s\n" "$key" "$b64"
    done
  fi
}

for ns in "${NAMESPACES[@]}"; do
  tmpfile=$(mktemp)
  mk_secret_yaml "$ns" > "$tmpfile"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "---"
    cat "$tmpfile"
    echo "# would seal with scope=$SCOPE -> ${OUT_DIR}/${NAME}-${ns}.sealed.yaml" >&2
    rm -f "$tmpfile"
    continue
  fi

  out="${OUT_DIR}/${NAME}-${ns}.sealed.yaml"
  kubeseal \
    --scope "$SCOPE" \
    --controller-namespace "$CTRL_NS" \
    --controller-name "$CTRL_NAME" \
    --format yaml < "$tmpfile" > "$out"
  rm -f "$tmpfile"
  echo "Wrote $out"
done

echo "Done. Remember to add the generated files to your kustomization 'resources' and apply."

