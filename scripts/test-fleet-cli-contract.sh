#!/usr/bin/env bash
set -eu

revision="$(jq -r .revision fleet/controller.json)"
attestation="$(mktemp)"
trap 'rm -f "$attestation"' EXIT
jq -n --arg revision "$revision" '{
  source: "blogle/sdlc",
  repository_id: 1402311485,
  commit_sha: $revision,
  reachable_from_protected: true,
  immutable: true,
  verified_by: "dotfiles-trusted-controller"
}' > "$attestation"
set +e
output="$(nix run "github:blogle/sdlc?rev=${revision}#packages.x86_64-linux.sdlc" -- \
  fleet plan \
  --manifest fleet/manifest.yaml \
  --policy fleet/policy.json \
  --attestation "$attestation" \
  --consumer-pin "${revision}" \
  --trusted-bypass-user-id 1 2>&1)"
status=$?
set -e

# This fixture intentionally has no real human bypass ID. The real pinned CLI
# must parse the complete prepare contract and then fail closed on that input.
if test "$status" -eq 0; then
  printf '%s\n' "contract unexpectedly succeeded:" >&2
  printf '%s\n' "${output:0:4000}" >&2
  exit 1
fi
if ! printf '%s\n' "$output" | grep -q "bypass identity"; then
  printf '%s\n' "contract failed for an unexpected reason (status $status):" >&2
  printf '%s\n' "${output:0:4000}" >&2
  exit 1
fi
