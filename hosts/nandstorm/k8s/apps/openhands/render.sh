#!/usr/bin/env bash
set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helm template openhands \
  "$here/vendor/agent-canvas" \
  --namespace openhands \
  --values "$here/values.yaml" \
  >"$here/rendered.yaml"

echo "rendered $here/rendered.yaml"
