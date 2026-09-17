# Lific v2.8.0 Deployment

This directory contains the Kubernetes manifests for deploying Lific v2.8.0 (issue tracking software with MCP support) to the nandstorm k3s cluster.

## Overview

- **Namespace**: `lific`
- **Hostname**: `https://lific.thejeffer.net`
- **Upstream Source**: https://github.com/VoidNullable/lific
- **Version**: v2.8.0 (specific tag, not `latest` or `master`)
- **Container Image**: Built from upstream Dockerfile and published to GHCR
- **Image Source**: `ghcr.io/blogle/lific@sha256:27ad9b7c585c57c9b07ac56222afe776e31ac767b34785d312b644eb9de6e1b7` (immutable digest)
- **Architecture**: Single binary with embedded SQLite, Rust backend, Bun-built web UI
- **Ingress**: Traefik with cert-manager (Let's Encrypt production issuer)
- **Persistence**: OpenEBS ZFS CSI StorageClass (`openebs-zfspv`)

## Storage Configuration

Lific uses a single PersistentVolumeClaim for all data:

| PVC Name | Size | Access Mode | StorageClass | Mount Path | Contents |
|----------|------|-------------|--------------|------------|----------|
| `lific-data` | 10Gi | ReadWriteOnce | openebs-zfspv | `/data` | SQLite database (`/data/lific.db`), attachments, automatic backups (`/data/backups/`) |

## Container Image

The Lific image is built from the exact upstream v2.8.0 tag:

- **Build Script**: `addrspace/apps/lific/build-image.sh`
- **Source**: https://github.com/VoidNullable/lific/tree/v2.8.0
- **Builder**: Docker Buildx (linux/amd64)
- **Registry**: GHCR (GitHub Container Registry)
- **Image**: `ghcr.io/blogle/lific:v2.8.0` (immutable digest referenced)
- **No Modifications**: Uses upstream Dockerfile unchanged

Image build process:
1. Clone `v2.8.0` tag from VoidNullable/lific
2. Build multi-stage Docker image (web UI with Bun, binary with Rust)
3. Push to `ghcr.io/blogle/lific:v2.8.0`
4. Retrieve immutable digest for Kubernetes deployment
5. Clean temporary workspace

## Resource Configuration

Lific runs as a single replica with Recreate strategy (required for SQLite):

| Resource | Requests | Limits |
|----------|----------|--------|
| CPU | 25m | 500m |
| Memory | 64Mi | 512Mi |

## Security Context

- Runs as non-root user: UID/GID 65532
- Read-only root filesystem
- No privilege escalation
- All capabilities dropped
- fsGroup: 65532 for volume ownership

## MCP Support

Lific includes built-in MCP (Model Context Protocol) server:
- **Endpoint**: `https://lific.thejeffer.net/mcp`
- **Authentication**: Required (matches web UI auth)
- **Transports**: HTTP (SSE) and WebSocket
- **Configuration**: No additional setup needed; MCP is enabled by default

## Access

After deployment, Lific will be available at:
- **Web UI**: https://lific.thejeffer.net
- **MCP Endpoint**: https://lific.thejeffer.net/mcp
- **Health Check**: https://lific.thejeffer.net/api/health (returns `ok`)

## Deployment

Managed via the repository's standard deployment mechanism:

```bash
# Apply via kustomize (from repository root)
kubectl apply -k addrspace/apps/
```

Or if using Flux/Argo CD, commit and push changes.

## Validation

```bash
# Check deployed resources
kubectl -n lific get all
kubectl -n lific get pvc
kubectl -n lific get deploy

# Verify TLS certificate
kubectl -n lific get certificate
kubectl -n lific get secret lific-tls

# Test health endpoint (internal)
kubectl run -n lific lific-health-test --rm -i --restart=Never \
  --image=curlimages/curl -- curl -fsS http://lific:3456/api/health

# Test health endpoint (external)
curl -fsS https://lific.thejeffer.net/api/health

# Test MCP endpoint (should require auth, not 404)
curl -fsSI https://lific.thejeffer.net/mcp
```

## Persistence

All Lific data is stored in the `lific-data` PVC:
- **SQLite Database**: `/data/lific.db` (contains issues, users, projects, etc.)
- **Attachments**: Stored in `/data/attachments/` (managed automatically)
- **Backups**: Automatic hourly backups to `/data/backups/` (retains 168 = 7 days)

## Backup & Recovery

The PVC should be snapshotted at the storage layer (OpenEBS ZFS) for backups.
The PVC is not deleted when removing the Deployment to prevent accidental data loss.

## Removal

To remove Lific while preserving data:
```bash
# Remove workloads but keep PVC
kubectl delete -k addrspace/apps/lific/

# PVC remains intact and can be re-attached by redeploying
# To delete PVC explicitly (DANGEROUS - data loss):
# kubectl delete pvc -n lific lific-data
```

## Post-Deployment Configuration

After both human users have created accounts:
1. Edit the ConfigMap: `kubectl -n lific edit configmap lific-config`
2. Change `allow_signup = false` in the `[auth]` section
3. Rollout restart: `kubectl -n lific rollout restart deployment/lific`

## Notes

- **Single Writer**: Lific uses SQLite and must run with exactly one replica (Recreate strategy)
- **No External Dependencies**: All components bundled in single binary
- **MCP Ready**: No additional configuration needed for MCP access
- **Resource Constraints**: Modest CPU/Memory allocation suitable for evaluation
