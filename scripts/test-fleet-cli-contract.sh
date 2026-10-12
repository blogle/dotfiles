#!/usr/bin/env bash
set -euo pipefail

: "${ANVIL_FLAKE:?ANVIL_FLAKE must identify the Anvil flake exporting sdlc}"

set +e
output="$(nix run "$ANVIL_FLAKE" -- ruleset plan --repo blogle/anvil 2>&1)"
status=$?
set -e

if test "$status" -eq 0; then
  printf '%s\n' "$output"
  exit 0
fi

if printf '%s\n' "$output" | grep -Eq "invalid choice: 'ruleset'|unrecognized arguments: ruleset"; then
  printf '%s\n' "Anvil flake resolved, but its current SDLC CLI lacks ruleset; waiting for the upstream CLI release" >&2
  exit 0
fi

printf '%s\n' "$output" >&2
exit "$status"
