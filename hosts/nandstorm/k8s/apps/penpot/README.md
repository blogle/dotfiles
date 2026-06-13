# Penpot Deployment with MCP Support

This directory contains the Kubernetes manifests for deploying Penpot with MCP (Model Context Protocol) support enabled.

## Architecture

- **Namespace**: `penpot`
- **Hostname**: `https://penpot.thejeffer.net`
- **Deployment Method**: Official Penpot Helm chart (v1.3.0) rendered to `penpot.yaml`
- **MCP Integration**: Native Helm chart MCP support (not the legacy standalone plugin server)
- **Ingress**: Traefik with cert-manager (Let's Encrypt production issuer)
- **Secrets**: SealedSecrets

## MCP Configuration

MCP is enabled via the Penpot Helm chart's native integration:

- `config.flags` includes `enable-mcp`
- MCP service runs as `ClusterIP` on ports 4401 (HTTP/SSE) and 4402 (WebSocket)
- All Penpot components (frontend, backend, exporter, mcp) run at 1 replica with HPA disabled
- MCP is exposed through the main Penpot ingress at `https://penpot.thejeffer.net/mcp/stream`

## User Workflow: Connecting an MCP Client

Each Penpot user must generate their own MCP key:

1. Log into Penpot at `https://penpot.thejeffer.net`
2. Go to **Your account → Integrations → MCP Server**
3. Enable MCP
4. Generate a personal MCP key
5. Copy the generated server URL (format: `https://penpot.thejeffer.net/mcp/stream?userToken=<USER_MCP_KEY>`)
6. Open the relevant Penpot file
7. Use **File → MCP Server → Connect**
8. Configure your MCP client with HTTP transport and the copied URL
9. Start with read-only prompts (listing pages/components) before allowing write operations

## Important Security Notes

- **MCP keys are per-user secrets** — do not commit them to this repository
- Each user generates their own key; keys are not shared
- The MCP service is internal-only (`ClusterIP`); no separate public MCP hostname is exposed

## Operational Limitations

- MCP acts on the currently focused Penpot page
- MCP can be active in only one browser tab per user/session
- Horizontal scaling is disabled for MCP and related components (frontend, backend, exporter) because MCP HA is not currently supported upstream
- Keep `replicaCount: 1` and `autoscaling.hpa.enabled: false` for all components until upstream supports MCP HA

## Deployment

```bash
# Apply via kustomize
kubectl apply -k /home/ogle/dotfiles/hosts/nandstorm/k8s/apps/penpot

# Or if using Flux/Argo CD, commit and push changes
```

## Validation

```bash
# Check deployed resources
kubectl -n penpot get deploy,svc,ingress
kubectl -n penpot get svc | grep -i mcp
kubectl -n penpot describe ingress penpot
kubectl -n penpot get certificate,secret

# Verify Penpot is reachable
curl -I https://penpot.thejeffer.net
```