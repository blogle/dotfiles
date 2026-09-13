# Nexus MCP gateway

Nexus is the aggregation boundary for MCP services used by external AI
clients. This initial deployment federates the existing Chadlands
`markdown-vault-mcp` service without changing that workload or its direct
OpenAI tunnel. GitHub is connected through GitHub's official remotely hosted
MCP server using its broad `all` toolset.

## Architecture

```text
ChatGPT
   |
OpenAI Secure MCP Tunnel
   |
Nexus
   +-- Chadlands markdown-vault-mcp
   +-- GitHub MCP
   +-- future services
```

The direct Chadlands OpenAI tunnel remains intentionally deployed during the
Nexus evaluation period. Do not remove it until Nexus has been proven reliable
and a separate cleanup change is approved.

## Version and image

The selected upstream stable release is Nexus `0.6.0` from
`Nexus-Router/nexus` / `grafbase/nexus`. The image is pinned to digest
`sha256:306ee6c0ae08036aea4a6cec424b27e6506b944f9e3d5c945ef34c1335988076`.

## Endpoints

Nexus listens on `0.0.0.0:8000`. The in-cluster MCP endpoint is:

```text
http://nexus.nexus.svc.cluster.local:8000/mcp
```

The health endpoint is `/health`. The private tailnet endpoint is
`https://nexus.thejeffer.net/mcp` after the Ingress certificate is ready.

From a tailnet client, verify the private route and then use an MCP client
against `https://nexus.thejeffer.net/mcp`. A minimal HTTP check is:

```sh
curl -fsS https://nexus.thejeffer.net/health
```

Initialize MCP, call `search` for a Markdown Vault capability, and call
`execute` with a harmless read-only `chadlands__stats` operation. The direct
Chadlands endpoint remains independently available at
`https://markdown-vault-mcp.thejeffer.net/mcp`.

## Adding another MCP server

1. Deploy or identify the downstream MCP endpoint.
2. Add it to the Nexus TOML configuration.
3. Add credentials through a strict-scoped SealedSecret if necessary.
4. Validate the configuration and local MCP endpoint.
5. Confirm `search` discovers its tools.
6. Confirm `execute` routes correctly.

Adding a downstream does not require a new ChatGPT connector, OpenAI tunnel,
or Nexus Service/Ingress.

## Secrets

The GitHub PAT is stored as `GITHUB_PAT` in the
`github-mcp-credentials` Secret. Nexus sends it to the official remote
endpoint `https://api.githubcopilot.com/mcp/x/all` through its supported
environment substitution. The planned second OpenAI tunnel will use
`nexus-tunnel-credentials`. Both must be generated with
`scripts/seal-secret.sh --scope strict`; plaintext credentials must not be
stored in this repository.

## Observability

Nexus exports OTLP gRPC to the existing Alloy gateway at
`alloy-otel.observability.svc.cluster.local:4317` with service name `nexus` and
resource attributes for `homelab`, `nandstorm`, and `mcp-gateway`. Logs are
collected by the existing Kubernetes Alloy log path. In Grafana, inspect Loki
for `{namespace="nexus",app="nexus"}` and Tempo for service `nexus`.

## Rollback

Stop or remove the Nexus application and its future tunnel. Continue using the
pre-existing direct Chadlands integration. That integration is deliberately
preserved until a future explicit deprecation change.
