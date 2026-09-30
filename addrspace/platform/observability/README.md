# Maple observability migration status

The upstream Maple repository currently publishes two Kubernetes collector
charts (`deploy/k8s-infra` 0.6.0 and `deploy/maple-otel` 0.3.0) and a custom
collector image (0.2.0). The `maple-k8s-infra` chart is used here for OTLP,
container logs, host/kubelet metrics, Kubernetes inventory, and events. A small
OTel Collector Prometheus receiver converts the retained DCGM and Exportarr
Prometheus endpoints to OTLP and forwards them to the Maple collector.

## Upstream deployment boundary (merge blocker)

At the current upstream `main` revision, the `deploy/` directory contains only
`docker-agent`, `k8s-infra`, and `maple-otel`. The top-level Compose file builds
API, web, ingest, alerting, scraper, and ElectricSQL from source; it also runs
Postgres and an OTLP collector. The API and MCP entry points are Cloudflare
Workers in `apps/api/src/worker.ts` and `apps/ai/src/worker.ts`, and upstream
does not publish their images or a supported Kubernetes deployment. Maple's
Kubernetes collector chart instead requires an ingest endpoint or a separately
initialized ClickHouse schema and credentials.

Accordingly, this repository cannot yet render a functional, self-hosted Maple
application/backend, obtain its database schema and credentials, or provide a
cluster-local authenticated MCP URL for Nexus. The collector values describe
the intended in-cluster ClickHouse endpoint and reference the required
`maple-clickhouse-credentials` Secret, which must not be fabricated. The PR
must remain draft until upstream publishes the application deployment contract
or the homelab has a supported, independently provisioned Maple backend and
sealed credentials. Do not point these exporters to Maple Cloud as a substitute.

## MCP contract

Upstream currently documents `https://api.maple.dev/mcp`, and source
`apps/ai/src/mcp/app.ts` implements stateless Streamable HTTP at `/mcp`.
Authentication is mandatory. In self-hosted mode, the internal-service-token
path requires both a configured `INTERNAL_SERVICE_TOKEN` and `x-org-id`; a root
password is not an MCP bearer token. Because the supported deployed endpoint is
hosted Cloudflare and no self-hosted API/MCP service currently exists, Nexus is
not configured to connect to a guessed or hosted endpoint.

## Collection

- In-cluster workload OTLP target: `http://maple-k8s-infra-agent.observability.svc.cluster.local:4317`
- OTLP/HTTP target: `http://maple-k8s-infra-agent.observability.svc.cluster.local:4318`
- OTel Kubernetes infrastructure chart collects pod logs, kubelet/host metrics,
  cluster resources and events; resource labels identify `nandstorm` and
  `homelab`.
- `prometheus-receiver.yaml` scrapes DCGM at 15 seconds and media Exportarr at
  60 seconds, then exports OTLP to the Maple agent.
- Nexus's native OTLP exporter is redirected to the Maple agent. Kubernetes
  logs and metrics remain available for components without a verified OTEL SDK
  or documented OTEL environment-variable support.

Nexus, Anvil, Lific, browser-mcp, kubernetes-mcp, Markdown Vault MCP, Dojo, and
Ollama still need per-application support verification before adding SDK- or
environment-specific configuration. Ollama does not provide general OTLP
emission in its current deployment. These workloads are covered by collector
logs and Kubernetes metrics in the meantime.
