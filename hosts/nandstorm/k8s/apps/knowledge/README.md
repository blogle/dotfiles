# Personal knowledge base

The `knowledge` namespace runs Ignis and markdown-vault-mcp against one shared,
human-owned Markdown root. Ignis is available at
`https://obsidian.thejeffer.net` through Traefik, cert-manager, and the existing
Tinyauth middleware. The MCP server is also available at
`https://markdown-vault-mcp.thejeffer.net/mcp` through the private
Traefik/MetalLB path for tailnet clients. The same pod's OpenAI tunnel-client
continues to reach
`http://127.0.0.1:8000/mcp` for ChatGPT.

The MCP pod disables Kubernetes service-link environment injection. Otherwise
the identically named Service injects `MARKDOWN_VAULT_MCP_PORT=tcp://...`, which
conflicts with the application's integer `MARKDOWN_VAULT_MCP_PORT` setting.

## Storage

`/persist/knowledge/vaults` is the durable source of truth. It is mounted in
full at `/vaults` in Ignis and `/data/vaults` in markdown-vault-mcp. No vault,
folder, or domain taxonomy is created by this deployment. Every top-level
directory users create under `/vaults` is an independent Ignis vault, while
markdown-vault-mcp recursively indexes their Markdown as one corpus.

Application-owned state uses dynamically provisioned `local-path` claims:

- `markdown-vault-mcp-state` at `/data/state` contains the rebuildable SQLite
  index, vector data, MCP/session state, key-value data, and FastEmbed cache.
- `ignis-data` at `/app/data` contains Ignis application data.
- `ignis-obsidian-app` at `/app/obsidian-app` caches Obsidian 1.12.7 assets.

The claims contain no human-authored Markdown. MCP state is disposable and can
be rebuilt from the vault, though retaining it avoids reindexing and repeated
model downloads.

Filesystem watching handles edits inside existing vaults. Adding a completely
new top-level vault may require `kubectl -n knowledge rollout restart
deployment/markdown-vault-mcp` or an explicit reindex so the watcher registers
the new directory.

## Tunnel credentials

`tunnel-credentials.sealed.yaml` is a namespace-scoped SealedSecret generated
from the proven POC's `CONTROL_PLANE_TUNNEL_ID` and
`CONTROL_PLANE_API_KEY`. Never commit an unsealed Secret. To rotate the values,
use `scripts/seal-secret.sh` with `--scope strict`, replace the sealed manifest,
and restart `deployment/markdown-vault-mcp`.

The sidecar runs tunnel-client 0.0.10 from the host's
`/run/current-system/sw/bin/tunnel-client`, mounted read-only into a pinned
Alpine runtime containing CA certificates. It does not mount `/nix/store`.

## Operations

```sh
kubectl -n knowledge get deployments,pods,pvc,service,ingress
kubectl -n knowledge describe ingress markdown-vault-mcp
kubectl -n knowledge logs deployment/markdown-vault-mcp -c markdown-vault-mcp
kubectl -n knowledge logs deployment/markdown-vault-mcp -c tunnel-client
kubectl -n knowledge rollout restart deployment/markdown-vault-mcp
kubectl -n knowledge rollout restart deployment/ignis
```
