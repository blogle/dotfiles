#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
CFG_PATH="$ROOT_DIR/m3u_gen_acestream.yaml"
OUT_PATH="$ROOT_DIR/out/dispatcharr_all_channels.m3u8"
ENGLISH_OUT_PATH="$ROOT_DIR/out/english_channels.m3u8"
NAMESPACE="media"
ACESTREAM_SERVICE="svc/aceserve"
PLAYLIST_LABEL="app=m3u-playlists"
PLAYLIST_DEST="/usr/share/nginx/html/dispatcharr_all_channels.m3u8"
ENGLISH_DEST="/usr/share/nginx/html/english_channels.m3u8"
PORT_FORWARD_LOG="/tmp/opencode/aceserve-port-forward.log"

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]] && kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
    kill "$PORT_FORWARD_PID"
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

mkdir -p "$ROOT_DIR/out"

# Generate English channels M3U from GitLab hanssettings repo
echo "Fetching English channels from GitLab..."
python3 "$ROOT_DIR/scripts/parse_hanssettings.py" --output "$ENGLISH_OUT_PATH"

# Ace Stream playlist generation
kubectl port-forward -n "$NAMESPACE" "$ACESTREAM_SERVICE" 6878:6878 >"$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!

for _ in {1..20}; do
  if curl --silent --fail "http://127.0.0.1:6878/webui/api/service?method=get_version" >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl --silent --fail "http://127.0.0.1:6878/webui/api/service?method=get_version" >/dev/null; then
  echo "Ace Stream port-forward did not become ready" >&2
  exit 1
fi

m3u_gen_acestream -c "$CFG_PATH"

PLAYLIST_POD=$(kubectl get pods -n "$NAMESPACE" -l "$PLAYLIST_LABEL" -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$PLAYLIST_POD" ]]; then
  echo "No m3u-playlists pod found in namespace $NAMESPACE" >&2
  exit 1
fi

# Copy to pod via kubectl (works from anywhere with kubeconfig)
kubectl cp "$OUT_PATH" "$NAMESPACE/$PLAYLIST_POD:$PLAYLIST_DEST"
kubectl cp "$ENGLISH_OUT_PATH" "$NAMESPACE/$PLAYLIST_POD:$ENGLISH_DEST"

printf 'Published %s\n' \
  "https://acestream.thejeffer.net/playlists/dispatcharr_all_channels.m3u8" \
  "https://acestream.thejeffer.net/playlists/english_channels.m3u8"