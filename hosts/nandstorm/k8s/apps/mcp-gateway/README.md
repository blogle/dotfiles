# Microsoft MCP Gateway (Traefik + SealedSecrets)

This deploys Microsoft MCP Gateway into the `mcp-gateway` namespace.

Design goals:
- Gateway stays "dumb": reverse proxy + management plane only (no LLM runtime).
- OpenClaw gets **no** Kubernetes credentials.
- Secrets for downstream tools live only in tool pods (or proxy pods), not in OpenClaw.
- Gateway is reachable only from LAN/tailnet and protected by Traefik BasicAuth.

## Deploy

```sh
kubectl apply -k hosts/nandstorm/k8s/apps/mcp-gateway
```

## Access

By default this Ingress is configured for:
- host: `mcpgateway.thejeffer.net`
- TLS secret: `mcpgateway-tls`

Adjust `hosts/nandstorm/k8s/apps/mcp-gateway/ingress.yaml` to your LAN/tailnet-only hostname.

### Port-forward (debug)

```sh
kubectl -n mcp-gateway port-forward svc/mcpgateway-service 8000:8000
```

## Smoke tests (curl)

If using port-forward:

```sh
export MCPGW=http://127.0.0.1:8000
```

If using Ingress:

```sh
export MCPGW=https://mcpgateway.thejeffer.net
```

### 1) Health check

```sh
curl -u "USER:PASS" -fsS "$MCPGW/adapters" | head
```

### 2) Create a sample adapter

NOTE: per upstream guidance, if `requiredRoles` is omitted, the gateway ALLOWs all **read** access by default.
Even though we front the gateway with Traefik auth, keep `requiredRoles` explicit in all workflows.

Example payload:

```json
{
  "name": "mcp-example",
  "imageName": "mcp-example",
  "imageVersion": "1.0.0",
  "description": "test",
  "requiredRoles": ["mcp.admin"]
}
```

```sh
curl -u "USER:PASS" -fsS \
  -H 'Content-Type: application/json' \
  -d @payload.json \
  "$MCPGW/adapters" | head
```

### 3) Connect to an adapter via streamable HTTP

```sh
curl -u "USER:PASS" -i \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "$MCPGW/adapters/mcp-example/mcp"
```

## Tool gateway router (/mcp)

Upstream runs a separate "Tool Gateway Router" StatefulSet named `toolgateway`.
Microsoft does not currently publish a public image for it, so we ship it **scaled to 0** in
`hosts/nandstorm/k8s/apps/mcp-gateway/statefulset-toolgateway.yaml`.

To enable it:
1. Build and push the tool gateway router image per upstream docs.
2. Update the image in `hosts/nandstorm/k8s/apps/mcp-gateway/statefulset-toolgateway.yaml`.
3. Set `replicas: 1` (or more).

Then you can route via:

```sh
curl -u "USER:PASS" -i -X POST "$MCPGW/mcp" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Proxying local/remote MCP servers (mcp-proxy)

The upstream `mcp-proxy` pattern supports:
- Bridging a stdio MCP server: set `MCP_COMMAND` and `MCP_ARGS`.
- Proxying a remote HTTP MCP server: set `MCP_PROXY_URL`.

Security note (upstream): only register trusted MCP servers, and enforce access controls so
workload identity / downstream credentials cannot be abused.

## Security posture

- **No secrets in OpenClaw:** OpenClaw talks only to the gateway endpoint. Downstream tool API keys belong in tool pods.
- **Ingress restrictions:** Traefik IP allowlist (LAN/tailnet) + Traefik BasicAuth.
- **RBAC:** gateway ServiceAccount has namespace-scoped permissions only (to create/update workloads it manages).
- **NetworkPolicies:** included for least-privilege intent. Enforcement depends on your CNI (k3s flannel may not enforce).

## Rotating Traefik BasicAuth secret

Regenerate the sealed secret and re-apply:

```sh
# Example: generate a new htpasswd line and seal it
./scripts/seal-secret.sh \
  --name mcpgateway-basicauth \
  -n mcp-gateway \
  --literal users='USER:APR1_HASH' \
  --output-dir hosts/nandstorm/k8s/apps/mcp-gateway \
  --scope strict

kubectl apply -k hosts/nandstorm/k8s/apps/mcp-gateway
```
