#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dir=hosts/nandstorm/k8s/apps/knowledge
if git -C "$root" grep -nEi '(CREATE TABLE|backend-api/conversations|message_created|function +render|fn +render|\.\./(telegram_collector|chatgpt_collector|ignis|chadlands)|scoped_workspace|/home/ogle)' -- "$dir/**"; then
  echo 'knowledge deployment boundary audit failed' >&2
  exit 1
fi
telegram=$(awk '/path: \/persist\/knowledge\/vaults/{sub(/^[[:space:]]*path:[[:space:]]*/, ""); print; exit}' "$root/$dir/telegram-deployment.yaml")
chatgpt=$(awk '/path: \/persist\/knowledge\/vaults/{sub(/^[[:space:]]*path:[[:space:]]*/, ""); print; exit}' "$root/$dir/chatgpt-collector.yaml")
test -n "$telegram" && test -n "$chatgpt" && test "$telegram" != "$chatgpt"
echo 'knowledge deployment boundary audit passed'
