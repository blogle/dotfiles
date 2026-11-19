# Garage61 MCP

Cluster-internal Garage61 telemetry MCP backend, exposed to ChatGPT through Nexus only.

Upstream: https://github.com/tqhdesilva/Garage61MCP

## Credentials

The namespace-scoped `garage61-credentials` SealedSecret supplies `GARAGE61_TOKEN`. On rotation, reseal the token for this namespace/name and update the Deployment's `checksum/credentials` annotation to the SHA-256 of the sealed manifest so the pod reloads it. Do not commit an unsealed token.

## Runtime

FastMCP upstream defaults to stdio; the Deployment imports its `mcp` instance and runs streamable HTTP on port 8000, path `/mcp`. The digest-pinned uv/Python image installs the source archive for the pinned upstream commit at startup. Dependency versions still resolve from upstream constraints at startup; use a prebuilt, digest-pinned application image for fully reproducible production deployment.

The upstream Git submodule for Lovely track data is not installed by uv. Track metadata tools requiring that dataset may return incomplete results; telemetry and API tools can still operate. Inspect startup logs and validate tools through Nexus after supplying credentials.

No ingress or standalone tunnel is required. Nexus routes traffic directly to `http://garage61-mcp.garage61-mcp.svc.cluster.local:8000/mcp`.
