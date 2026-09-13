#!/usr/bin/env bash
# seal-secrets.sh — regenerate sealed secrets for sandbox-server.
#
# Requires:
#   - kubectl access to the nandstorm cluster
#   - kubeseal installed locally
#   - The sealed-secrets controller running in the cluster
#
# Usage:
#   cd hosts/nandstorm/k8s/apps/openhands/sandbox-server
#   ./seal-secrets.sh

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
controller_ns=kube-system
controller_name=sealed-secrets-controller

echo "Reading api-key from openhands-runtime-secrets (openhands-sandboxes)..."
api_key=$(kubectl -n openhands-sandboxes get secret openhands-runtime-secrets \
  -o jsonpath='{.data.api-key}' | base64 -d)

if [[ -z "$api_key" ]]; then
  echo "ERROR: could not read api-key from openhands-runtime-secrets" >&2
  exit 1
fi

echo "Sealing sandbox-server-api-key..."
kubectl create secret generic sandbox-server-api-key \
  --namespace=openhands \
  --from-literal=api-key="$api_key" \
  --dry-run=client -o yaml \
  | kubeseal \
    --controller-namespace="$controller_ns" \
    --controller-name="$controller_name" \
    --format yaml \
    > "$here/sandbox-api-key.sealed.yaml"

echo "Wrote $here/sandbox-api-key.sealed.yaml"
echo "Done."
