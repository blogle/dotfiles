#!/usr/bin/env bash
set -eu

has_current_approval() {
  local reviews=$1
  local head=$2
  printf '%s' "$reviews" | jq -e --arg reviewer blogle --arg head "$head" \
    '[.[] | select(.user.login == $reviewer and .commit_id == $head and .state == "APPROVED")] | length > 0' \
    >/dev/null
}

stale='[{"user":{"login":"blogle"},"commit_id":"old","state":"APPROVED"}]'
absent='[]'
current='[{"user":{"login":"blogle"},"commit_id":"current","state":"APPROVED"}]'

if has_current_approval "$absent" current || has_current_approval "$stale" current; then
  printf '%s\n' "review fixture incorrectly accepted" >&2
  exit 1
fi
has_current_approval "$current" current
