# Garage61 MCP

Cluster-internal Garage61 telemetry MCP backend, exposed to ChatGPT through Nexus only.

Upstream: https://github.com/tqhdesilva/Garage61MCP

## Credentials

Before enabling this application, create a SealedSecret in namespace `garage61-mcp` that materializes a Kubernetes Secret named `garage61-credentials` with key `GARAGE61_TOKEN`. Obtain the token from https://garage61.net/developer. Do not commit an unsealed token.

## Runtime

FastMCP upstream defaults to stdio; the Deployment imports its `mcp` instance and runs streamable HTTP on port 8000, path `/mcp`. Dependencies resolve at startup via uv from the pinned upstream commit. Promote to a prebuilt, digest-pinned image for reproducible production deployment.

The upstream Git submodule for Lovely track data is not installed by uv. Track metadata tools requiring that dataset may return incomplete results; telemetry and API tools can still operate. Inspect startup logs and validate tools through Nexus after supplying credentials.

No ingress or standalone tunnel is required. Nexus routes traffic directly to `http://garage61-mcp.garage61-mcp.svc.cluster.local:8000/mcp`.
