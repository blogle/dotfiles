#!/usr/bin/env bash
set -euo pipefail

# Build and push Lific v2.8.0 to GHCR

# Determine authenticated GitHub owner
GHCR_OWNER=$(gh api user --jq '.login')
echo "Building for GHCR owner: $GHCR_OWNER"

# GHCR needs a token with package access for both the push and digest lookup.
gh auth token | docker login ghcr.io --username "$GHCR_OWNER" --password-stdin >/dev/null

# Work in a temporary directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Clone exactly v2.8.0
git clone --depth 1 --branch v2.8.0 https://github.com/VoidNullable/lific.git "$WORK_DIR/lific"
cd "$WORK_DIR/lific"

# Build the image
echo "Building Docker image..."
docker buildx build --platform linux/amd64 \
  -t ghcr.io/${GHCR_OWNER}/lific:v2.8.0 \
  --label org.opencontainers.image.source=https://github.com/VoidNullable/lific \
  --label org.opencontainers.image.version=v2.8.0 \
  --metadata-file "$WORK_DIR/build-metadata.json" \
  --push .

# buildx records the pushed manifest index digest in its metadata. docker
# inspect is deliberately avoided: it may return a stale local tag digest.
DIGEST_ONLY=$(jq -r '."containerimage.digest"' "$WORK_DIR/build-metadata.json")
echo "Image digest: $DIGEST_ONLY"

# Output for use in manifests
echo "DIGEST=$DIGEST_ONLY"
echo "IMAGE=ghcr.io/${GHCR_OWNER}/lific@${DIGEST_ONLY}"
