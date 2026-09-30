# ClickStack observability

## Topology choice

Official ClickStack documents three relevant deployment choices:

| Option | Upstream support | Decision |
| --- | --- | --- |
| All-in-one `docker.hyperdx.io/hyperdx/hyperdx-all-in-one` | Official local/testing image; combines UI, ClickHouse and collector. | Not used: upstream positions it for local testing; separate durable data storage and independent OTel configuration are required here. |
| Split HyperDX, ClickHouse, MongoDB and ClickStack OTel collector | Supported by the official HyperDX-only and ClickStack collector docs. | Supported, but requires more independently managed images/services. |
| Full ClickStack Helm v2 chart | Officially recommended for production Kubernetes; chart installs HyperDX, ClickHouse/Keeper, MongoDB and the ClickStack OTel collector. | Selected: one supported chart release plus its prerequisite operator release, configured for this single-node cluster. |

Pinned official chart versions are ClickStack `3.4.0` (HyperDX and collector
`2.39.1`) and ClickStack operators `1.1.0` (MongoDB operator `1.7.0`, ClickHouse
operator `0.0.7`, and OTel Collector subchart `0.146.1`). ClickHouse and Keeper
use `25.7-alpine`, pinned by OCI digest
`sha256:258d438215084cad2b4504749bd7046a869a82789983831df6348a737c1a85f6`;
MongoDB is pinned to `5.0.32`. The authoritative chart source snapshot is
ClickHouse/ClickStack-helm-charts commit `e5a3ddf3ebf9a60d97d0e59f6bd01b60dcd3c77e`.

## Storage and resource bounds

- ClickHouse: one shard, one replica; ClickHouse Keeper: one replica; MongoDB:
  one member. All three use OpenEBS ZFS LocalPV with
  `storageClassName: openebs-zfspv-retain`.
- Initial ClickHouse claim: 40Gi; Keeper: 5Gi; MongoDB: 5Gi. ClickHouse
  resources request 1 CPU/2Gi and limit 2 CPU/4Gi. HyperDX, the collector,
  Keeper, MongoDB, and their operators have bounded requests/limits.
- The `observability` quota permits old retained claims and new ClickStack
  claims to coexist during the migration. Neither PVCs nor backing ZFS datasets
  are deleted by this PR.

The ClickStack collector image runs its bundled canonical OTel-to-ClickHouse
schema migrations on startup. This produces ClickStack's `otel_logs`,
`otel_traces`, `otel_metrics_*`, and `hyperdx_sessions` schema; the manifests do
not hand-author OTel tables.

## Collection

The ClickStack OTel Collector uses its official standalone ClickHouse-export
configuration (no OpAMP requirement for internal collection). The collector
DaemonSet's ClusterIP Service is the stable producer endpoint:

- gRPC: `clickstack-otel-collector.observability.svc.cluster.local:4317`
- HTTP: `http://clickstack-otel-collector.observability.svc.cluster.local:4318`

The official collector image is extended with a supported custom configuration
that retains OTLP traces, metrics and logs; adds Kubernetes pod/container
filelogs, host/kubelet/cluster metrics, Kubernetes metadata and resource
attributes `k8s.cluster.name=nandstorm` and
`deployment.environment.name=homelab`; and scrapes DCGM every 15 seconds plus
Sonarr/Radarr/Prowlarr Exportarr every 60 seconds. ClickStack's own ClickHouse
exporter remains the writer for all signals. Collector OTLP ports are
ClusterIP-only, not Ingress-exposed.

## UI authentication and MCP

HyperDX is exposed at `https://clickstack.thejeffer.net` through the existing
Traefik `letsencrypt` issuer and `auth-sso-auth` / `auth-sso-errors` TinyAuth
middleware. HyperDX local user authentication remains enabled behind that
outer Pocket ID boundary.

ClickStack's native MCP server is bundled into HyperDX. The verified OSS
contract is stateless Streamable HTTP at `/api/mcp` on the frontend service,
with `Authorization: Bearer <Personal API Access Key>`. The Nexus downstream is
configured for the cluster-local `clickstack-app` service on port 3000. Its
Bearer key is supplied through a Secret reference, not the ConfigMap. Supported
tools include log/trace/metric query and search, SQL, dashboards, alerts, saved
searches and team information.

## Sealed-secret setup gate

The ClickStack K3s `HelmChart` consumes a `values.yaml` key from a SealedSecret
named `clickstack-values` in `kube-system`; this values document supplies
ClickHouse, MongoDB and HyperDX credentials. No credential values are stored in
Git. The current Anvil session has no Kubernetes context or SealedSecrets public
certificate, so the encrypted values file cannot be generated here. Before
reconciling the ClickStack HelmChart, generate `clickstack-values.yaml` locally
with strong random values for `hyperdx.secrets.HYPERDX_API_KEY`,
`hyperdx.secrets.CLICKHOUSE_PASSWORD`,
`hyperdx.secrets.CLICKHOUSE_APP_PASSWORD`, and
`hyperdx.secrets.MONGODB_PASSWORD`. Then seal it using the repo's existing
controller:

```sh
kubectl create secret generic clickstack-values \
  --namespace kube-system \
  --from-file=values.yaml=clickstack-values.yaml \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > addrspace/platform/observability/clickstack-values.sealed.yaml
```

Add `clickstack-values.sealed.yaml` to this directory's `kustomization.yaml`
resources so Flux creates the `kube-system` SealedSecret before the ClickStack
HelmChart is reconciled. Keep the local plaintext file outside Git and remove it
after sealing.

The personal MCP API key is created in HyperDX Team Settings after initial user
registration. Seal it as `clickstack-mcp-credentials` in `nexus` (key
`api-key`), then restart Nexus so its startup-snapshotted tool catalog includes
ClickStack. Add the resulting SealedSecret to `addrspace/apps/nexus/kustomization.yaml`.
The deployment requires this key before a replacement Nexus pod starts; with
the rolling update strategy the existing replica remains available while the
credential is missing. This key is not the OTel ingestion key. The PR must
remain draft until both sealed credentials exist and the MCP catalog is verified.

## Application OTEL support audit

| Workload | Evidence and result |
| --- | --- |
| Nexus | Its `telemetry.exporters.otlp` supports the ClickStack gRPC endpoint; the OTel exporter needs no auth header in the internal standalone collector mode. |
| Kubernetes MCP | The pinned Quay image tracks the current upstream server. Upstream `docs/OTEL.md` documents standard `OTEL_EXPORTER_OTLP_ENDPOINT`, protocol, service name/resource attributes, traces and metrics. The Deployment sets these to ClickStack. |
| Anvil | Inspected current `blogle/anvil` source; no OTEL SDK/exporter or `OTEL_*` configuration found. Collect Kubernetes logs/metrics. |
| Lific | Its checked-in TOML has server/database/backup/log/auth settings only; source repository is not public. No OTEL variable is guessed; collect Kubernetes logs/metrics. |
| browser-mcp | The deployed `mcp-proxy@6.7.18` and `agent-browser@0.37.1` package metadata/source exposes no configured OTEL SDK/exporter for this pod. Collect Kubernetes logs/metrics. |
| Markdown Vault MCP | Inspected its deployed config and current source; no OTEL SDK/exporter or `OTEL_*` settings found. Collect Kubernetes logs/metrics. |
| Dojo | Inspected the production base pin `e522168b898108d8ddcce35e9c266bc7b956b12b` and current source; no OTEL SDK/exporter or `OTEL_*` config found. Collect Kubernetes logs/metrics. |
| Ollama/AI | No verified OTLP exporter or documented OTEL environment interface in the deployed Ollama version. Collect pod logs, workload metrics and DCGM GPU metrics. |

No unsupported application telemetry variables are added. The ClickStack
Kubernetes collector is the fallback for applications without verified SDK
support.

## Safe legacy retirement (Flux prune remains disabled)

Operators and ClickStack reconcile before the apps layer; the apps Flux
Kustomization depends on the ClickStack health checks before Nexus and supported
OTLP producers are redirected. `prune: false` is unchanged for all cluster
layers, so removing legacy definitions from Git does not uninstall the live
releases. After confirming ClickStack UI, OTel schema/ingestion and Nexus MCP
tools, perform a reviewed, targeted retirement of the old K3s HelmCharts
(`kube-prometheus-stack`, `grafana`, `loki`, `tempo`, `alloy-logs`, `alloy-otel`,
`blackbox-exporter`) and obsolete named Prometheus Operator CR instances. Inspect
all remaining `ServiceMonitor`, `PodMonitor`, `Probe` and `PrometheusRule`
instances before CRD removal. Retire the Grafana OIDC sealed credential and its
TinyAuth client configuration in the same reviewed cleanup. Do not delete
retained PVCs, PVs or ZFS datasets.
