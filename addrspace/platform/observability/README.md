# Maple observability migration status

The branch contains candidate manifests for upstream Maple Kubernetes
collectors (`deploy/k8s-infra` 0.6.0) and an OTel Prometheus receiver for DCGM
and Exportarr. They are deliberately not included in this kustomization: there
is no working self-hosted Maple ingest/backend destination to receive telemetry.
The legacy stack remains live until a functioning Maple deployment is
available and verified.

## Upstream deployment boundary (merge blocker)

At upstream `main` (inspected at `671e80a`), `deploy/` contains only
`docker-agent`, `k8s-infra`, and `maple-otel`. The MapleTechLabs GitHub Container
Registry lists only those collector images and charts; it publishes no API,
web, ingest, alerting, scraper, or MCP images. The top-level
`docker-compose.yml` is not a runnable self-host deployment in this revision:
it references `apps/alerting/Dockerfile`, which is absent, and starts the API
image with `bun run start` although `apps/api/package.json` has no `start`
script. It also has no ClickHouse service. `docker-compose.development.yml`
starts only Postgres, ElectricSQL, ClickHouse and a collector, not the app/MCP
workers. The API and MCP entry points are Cloudflare Workers in
`apps/api/src/worker.ts` and `apps/ai/src/worker.ts`, with no published
container/production Kubernetes runtime.

Accordingly, this repository cannot yet render a functional, self-hosted Maple
application/backend, obtain its database schema and credentials, or provide a
cluster-local authenticated MCP URL for Nexus. The candidate collector chart
references a hypothetical ClickHouse service and absent
`maple-clickhouse-credentials` Secret; it will not start successfully. This is
a hard blocker, not a completed cutover. The collector manifests are not
activated, Nexus remains pointed at the currently running Alloy service, and
Flux pruning remains disabled. Do not merge or activate a Maple cutover until an
upstream-supported app/MCP deployment and sealed backend credentials are
available. Do not point exporters to Maple Cloud as a substitute.

The current `maple start` binary is not a production substitute. Upstream
`docs/local-mode.md` (same revision) explicitly describes it as a local try-it
mode with “no auth”; binding it beyond loopback exposes unauthenticated OTLP and
`/local/query`. It also does not implement Maple MCP, so the homelab's outer
Traefik/TinyAuth boundary would not provide the requested in-cluster MCP contract
or authenticate cluster-local clients.

## MCP contract

Upstream currently documents `https://api.maple.dev/mcp`, and source
`apps/ai/src/mcp/app.ts` implements stateless Streamable HTTP at `/mcp`.
Authentication is mandatory. In self-hosted mode, the internal-service-token
path requires both a configured `INTERNAL_SERVICE_TOKEN` and `x-org-id`; a root
password is not an MCP bearer token. Because the supported deployed endpoint is
hosted Cloudflare and no self-hosted API/MCP service currently exists, Nexus is
not configured to connect to a guessed or hosted endpoint.

## Candidate collection design (not active)

- Proposed in-cluster workload OTLP targets:
  `maple-k8s-infra-agent.observability.svc.cluster.local:4317` (gRPC) and
  `:4318` (HTTP).
- Candidate upstream collector config enables pod logs, kubelet/host metrics,
  cluster resources and events with `nandstorm`/`homelab` resource identity.
- Candidate Prometheus receiver scrapes DCGM at 15s and media Exportarr at 60s.
- These resources are not referenced by the observability Kustomization. Nexus
  remains pointed at the currently running Alloy OTLP endpoint. No producer is
  redirected until the Maple backend and collectors pass an end-to-end smoke test.

## Application telemetry audit

| Workload | Evidence/configuration | Result |
| --- | --- | --- |
| Nexus | `addrspace/apps/nexus/configmap.yaml` has a native OTLP exporter. | Supported natively; retained on Alloy until a working Maple endpoint exists. |
| Kubernetes MCP | Pinned `quay.io/containers/kubernetes_mcp_server` image; upstream `docs/OTEL.md` documents `OTEL_EXPORTER_OTLP_ENDPOINT`, protocol, service name/resource attrs, traces and metrics. | Verified support; candidate variables are withheld until Maple is available. |
| Anvil | Inspected current `blogle/anvil` source; no OTEL SDK/exporter or `OTEL_*` configuration found. | No app telemetry configuration; collect pod logs and Kubernetes metrics. |
| Lific | Deployed image is private; public `blogle/lific` source is unavailable. `configmap.yaml` exposes only server/database/backup/log/auth settings and no OTEL variables. | No verified OTEL support; collect pod logs and Kubernetes metrics. |
| browser-mcp | Deployment runs `mcp-proxy@6.7.18` and `agent-browser@0.37.1`; this pod has no configured telemetry SDK/exporter or documented OTEL settings. | No verified app-level telemetry; collect pod logs and Kubernetes metrics. |
| Markdown Vault MCP | Inspected current `blogle/markdown-vault-mcp` source/config; no OTEL SDK/exporter or `OTEL_*` settings found. | No app telemetry configuration; collect pod logs and Kubernetes metrics. |
| Dojo | Inspected current `blogle/dojo2` source; no OTEL SDK/exporter or `OTEL_*` settings found. | No app telemetry configuration; collect pod logs and Kubernetes metrics. |
| Ollama/AI | Current Ollama container config has no verified OTLP exporter or documented OTEL environment interface. | Collect pod logs, kubelet/workload metrics, and DCGM GPU metrics. |

No unsupported application variables are invented. After the backend exists,
Maple's Kubernetes collector should provide Kubernetes logs/metrics for apps
without verified app-level exporters.

## Safe retirement with Flux pruning disabled

`addrspace-apps`, `addrspace-platform`, and `addrspace-controllers` intentionally
retain `prune: false`. Removing the HelmChart/CRD consumers from Git does not
uninstall the active releases; the existing Grafana stack remains running while
this PR is blocked. After Maple ingestion, UI, storage and MCP are installed and
smoke-tested, operators must perform a reviewed, targeted retirement of the old
K3s HelmChart objects and legacy CR instances. The chart objects to retire are
`kube-prometheus-stack`, `grafana`, `loki`, `tempo`, `alloy-logs`, `alloy-otel`,
and `blackbox-exporter` in `kube-system`. Remove them only after verifying Maple
end-to-end; first inspect remaining `ServiceMonitor`, `PodMonitor`, `Probe`, and
`PrometheusRule` objects and delete only obsolete instances. Leave PV/PVC data
untouched: do not delete retained ZFS PVs or datasets as part of retirement.
