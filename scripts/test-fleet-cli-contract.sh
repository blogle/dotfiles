#!/usr/bin/env bash
set -euo pipefail

: "${ANVIL_DIR:?ANVIL_DIR must point at the checked-out Anvil tree}"
test -f "$ANVIL_DIR/.github/repository-policy.json"
(cd "$ANVIL_DIR" && nix run .#sdlc -- policy plan --repo blogle/anvil)
