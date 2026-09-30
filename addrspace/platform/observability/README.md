# Maple observability migration status

The branch contains candidate manifests for upstream Maple Kubernetes
collectors (`deploy/k8s-infra` 0.6.0) and an OTel Prometheus receiver for DCGM
and Exportarr. They are deliberately not included in this kustomization: there
is no working self-hosted Maple ingest/backend destination to receive telemetry.
The legacy stack remains live until a functioning Maple deployment is
available and verified.

## Upstream deployment boundary (merge blocker)

At upstream `main` commit
`671e80a806a0c714293eefec338f891bcda4c39f`, `deploy/` contains only
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

I ran the Compose checks against this checkout: `docker-compose config --quiet`
passes with a temporary local `.env`, but `docker-compose build --check
alerting` fails on the missing Dockerfile. The API image's command was tested
with Bun 1.4.2 and fails with `Script not found "start"`. Thus the syntactically
valid root Compose file does not produce a running self-hosted application.

`docker-compose config --quiet` succeeds only after creating the required local
`.env`; it does not validate build contexts or container startup. Actual
`docker-compose build --check alerting` fails because the alerting Dockerfile is
missing, and executing the API Dockerfile command from `apps/api/` fails because
the `start` package script is absent.

### Pinned-source build/runtime audit

The upstream source has individual Dockerfiles for the static `apps/web` site,
Rust `apps/ingest`, `apps/scraper`, and an `apps/electric` service. Those builds
alone do not make a working product stack:

| Service | Upstream build/runtime contract | Self-host K8s result |
| --- | --- | --- |
| Web | `apps/web/Dockerfile` builds a static SPA; `VITE_API_BASE_URL` and auth mode are build args. | Buildable, but depends on a routable API URL. |
| Ingest | `apps/ingest/Dockerfile` compiles the Rust gateway. | Buildable; requires upstream API/internal auth contracts and a running collector. |
| Scraper | `apps/scraper/Dockerfile` builds the Bun process. | Buildable; it calls the API and ingest endpoints. |
| Electric | `apps/electric/Dockerfile` exists; `alchemy.run.ts` creates its production service on ECS. | Buildable, but its upstream deployment factory is ECS-specific. |
| API | `apps/api/Dockerfile` ends with `bun run start`, but `apps/api/package.json` has no `start` script. `apps/api/src/worker.ts` exports an `Alchemy.Worker` with Cloudflare `WorkerEnvironment`, service bindings, Durable Object, queues, cron, and Workflow resources. | No runnable upstream container entry point; needs a Worker runtime/bindings adapter. |
| Alerting | `apps/alerting/src/worker.ts` is an Alchemy Cloudflare Worker; the root Compose references the nonexistent `apps/alerting/Dockerfile`. | No upstream image/build target. |
| AI/MCP | `apps/ai/src/worker.ts` exports the Worker hosting MCP and `ChatSessionObject`; API forwards `/mcp` over a Cloudflare service binding. | No container target; MCP cannot be moved to a local service without a supported Worker runtime. |
| Electric Sync | `apps/electric-sync/src/worker.ts` is an Alchemy Worker. | No container target. |

The individually buildable `web`, Rust `ingest`, `scraper`, and Electric images
do not complete this table's missing API/MCP runtime. Publishing that subset as
`ghcr.io/blogle` images would still leave the product unable to serve its API,
dashboard queries, and MCP tools; therefore this PR does not add an image-publish
workflow for a non-runnable stack. The API Dockerfile itself was tested at its
declared working directory with upstream Bun 1.4.2: `bun run start` exits with
`Script not found "start"`.

The dotfiles repository currently has no Docker/Buildx image-publishing
workflow; its Kubernetes workflow validates manifests and already-published
artifacts. Adding a GHCR workflow for only the buildable subset would publish
images that cannot serve Maple without the missing API/MCP Workers, so it is not
a functional workaround.

`docs/infra.md` (same upstream revision) says `bun dev` runs these Workers through
Alchemy's **local development runtime**, while non-Workers are `Command.Dev`
children and that command is a no-op on deploy. It is not a production adapter.
The upstream dev adapter was actually attempted from the pinned source after
`bun install --frozen-lockfile` and `bun run alchemy:build-deps` succeeded:
`ALCHEMY_LOCAL_STATE=1 bun run dev api ai` fails during stack planning with
`FlociError: docker run failed: Executable not found in $PATH: "docker"`.
Alchemy Floci launches local Worker containers through Docker; this repo's
`nandstorm` host runs k3s/containerd and has no Docker socket. Provisioning a
privileged nested Docker daemon solely to run an explicitly dev-only adapter is
not a production-quality Kubernetes runtime.

Even with that daemon, the dev adapter is not externally routable as-is:
`alchemy.run.ts` sets API/web/ingest URLs from `Portless.routeUrl`, which hardcodes
`https://<app>.localhost` (`packages/infra/src/dev-urls.ts`), while
`lib/alchemy-portless/src/Route.ts` binds workers on `127.0.0.1`. External
browsers resolve `.localhost` to their own loopback. `MAPLE_PG_URL` is also
documented in `.env.example` as required to configure the dev Hyperdrive origin;
the dev binding itself dials `localhost:5499`. No unmodified upstream production
adapter translates these local-only bindings/routes into self-hosted Kubernetes
Services. An adapter would require source/runtime changes or a privileged local
development stack, neither of which is a sound supported self-host deployment.

### Database/schema initialization

Canonical application Postgres migrations are `packages/db/drizzle`, applied
upstream with `bun run db:migrate:local`. Maple telemetry ClickHouse schema is
maintained by `packages/clickhouse-cli`; upstream development docs use
`bun run --cwd packages/clickhouse-cli start apply --url=... --user=maple
--password=... --database=default`. These steps could initialize storage once
the required API/MCP worker runtime and sealed self-host credentials are
available. The collector candidate is not activated against an uninitialized
ClickHouse database.

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
