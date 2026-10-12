#!/usr/bin/env bash
set -eu

revision="$(jq -r .revision fleet/controller.json)"
set +e
output="$(nix run "github:blogle/sdlc?rev=${revision}#packages.x86_64-linux.sdlc" -- \
  fleet plan \
  --manifest fleet/manifest.yaml \
  --policy fleet/policy.json \
  --attestation /dev/null \
  --consumer-pin "${revision}" \
  --trusted-bypass-user-id 1 2>&1)"
status=$?
set -e

# This fixture intentionally has no real human bypass ID. The real pinned CLI
# must parse the complete prepare contract and then fail closed on that input.
test "$status" -ne 0
printf '%s\n' "$output" | grep -q "bypass identity"
