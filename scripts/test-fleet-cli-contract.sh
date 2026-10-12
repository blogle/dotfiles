#!/usr/bin/env bash
set -euo pipefail

: "${ANVIL_FLAKE:?ANVIL_FLAKE must identify the Anvil flake exporting sdlc}"

if ! output="$(nix run "$ANVIL_FLAKE" -- ruleset plan --repo blogle/anvil 2>&1)"; then
  printf '%s\n' "Anvil flake resolved, but its SDLC CLI cannot run 'ruleset plan'; pin the upstream ruleset implementation before retrying:" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
printf '%s\n' "$output"
