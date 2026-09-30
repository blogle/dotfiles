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

The ClickStack OTel Collector uses the official standalone ClickHouse-export
configuration. `OPAMP_SERVER_URL` is explicitly empty: the bundled image's
entrypoint then runs its production standalone path with `config.yaml`,
`standalone-config.yaml`, and the mounted `CUSTOM_OTELCOL_CONFIG_FILE`; before
starting the collector it runs the bundled ClickHouse schema migration tool.
The standalone base config supplies ClickStack's OTLP receiver, ClickHouse
exporters, routing connector, and base log transforms. The mounted custom config
adds the Kubernetes/host/Prometheus receivers and re-declares the full signal
pipelines, retaining both standard and rrweb/session log routes. This opts out
of remotely managed OpAMP pipeline config so the explicit custom pipelines are
authoritative; ClickStack's UI/API and MCP remain HyperDX services. The chart's
documented config-file merge mechanism supports custom configs in standalone
mode as well as its default supervisor mode.

The collector DaemonSet's ClusterIP Service is the stable producer endpoint:

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

I rendered the exact `3.4.0` chart values and inspected its generated
DaemonSet/RBAC. The service account token is mounted; `K8S_NODE_NAME` comes from
`spec.nodeName` and `K8S_NODE_IP` from `status.hostIP`. `kubeletMetrics` grants
`nodes/stats`; `kubernetesAttributes` grants pod/namespace and ReplicaSet
lookups; `clusterMetrics` grants the Kubernetes objects plus apps/batch/
autoscaling required by `k8s_cluster` and Prometheus pod service discovery. The
collector mounts `/var/log/pods` and host `/` read-only, with host-to-container
mount propagation for host metrics. The generic `logsCollection` preset is
disabled because it also mounts `/var/lib/docker/containers`, which is not used
by this containerd node; the chart is instead given an explicit
`/var/log/pods` hostPath volume/mount (`type: Directory`) for the filelog
receiver. Rendered gRPC/HTTP services expose 4317 and 4318 on ClusterIP.

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

## Credential generation and staged bootstrap

The ClickStack 3.4.0 chart uses `hyperdx.secrets` as the unified source and
renders it into `clickstack-secret` for HyperDX and the collector. The MongoDB
chart template also bridges `MONGODB_PASSWORD` to the `password` key required by
MongoDBCommunity. The ClickHouse user templates use the two ClickHouse values
to render password hashes into the operator CR. Auditing every chart template
and default values file shows four required credential keys:

| `hyperdx.secrets` key | Consumer |
| --- | --- |
| `HYPERDX_API_KEY` | HyperDX app and bundled collector environment. |
| `CLICKHOUSE_PASSWORD` | OTel collector/migrations user. |
| `CLICKHOUSE_APP_PASSWORD` | HyperDX's ClickHouse query user. |
| `MONGODB_PASSWORD` | HyperDX and the MongoDBCommunity user Secret. |

Chart 3.4.0 does not template an Express/session secret; no additional session
key is required by this chart release. The K3s Helm controller requires
`valuesSecrets` by default and reads `keys` from a Secret in the HelmChart's
namespace. Here `clickstack-values` must be in `kube-system`, with a key named
`values.yaml`. `ignoreUpdates` remains false: absent Secret/key prevents chart
installation; adding/changing the sealed values later triggers an upgrade. Its
YAML overrides the non-secret `valuesContent` map at the same nested
`hyperdx.secrets` path. K3s helm-controller projects `valuesContent` to the
first numbered `/config/values-*.yaml` file and the referenced Secret key to
the next one; `klipper-helm` passes that glob-ordered list as repeated Helm
`--values` arguments, so the sealed Secret file is the later/higher-precedence
override. I rendered the chart with the same two-file order and verified the
unified Secret, MongoDB password bridge, and ClickHouse password hashes.

Generate and seal the bootstrap file with the repo helper:

```sh
nix develop --command bash addrspace/scripts/clickstack-seal-secret.sh values
```

It fetches the Sealed Secrets **public** certificate from the current
`sealed-secrets-controller` in `kube-system`, generates strong random
credentials, seals a strict-scope Secret, and writes only ciphertext to
`addrspace/platform/observability/clickstack-values.sealed.yaml`. Plaintext is
kept in a mode-0700 temporary directory that is removed on exit; the script
does not apply resources and refuses to overwrite an existing output. Add the
generated path to this directory's `kustomization.yaml`. This platform layer
reconciles before the operators and ClickStack charts, so the values Secret is
available before K3s Helm starts.

### MCP token lifecycle (no Flux dependency deadlock)

The native HyperDX MCP endpoint at `/api/mcp` authenticates with a Personal API
Access Key created in Team Settings after the first account/team is initialized.
That key cannot be generated as part of the initial Helm bootstrap. The Flux
ordering intentionally handles this in two phases:

1. ClickStack waits only for its HyperDX Deployment and collector DaemonSet; it
   does not depend on Nexus or the MCP token.
2. Once ClickStack is healthy, the apps layer applies the TinyAuth hostname,
   Nexus MCP config, and a Nexus Deployment that requires
   `clickstack-mcp-credentials`. The default Deployment strategy is
   `RollingUpdate`; with one replica its old pod remains available while a new
   pod waits for the missing Secret. The apps Kustomization reports NotReady on
   its Nexus health check, but that does not roll back or block ClickStack.
3. Create the user/team in HyperDX, create a Personal API Access Key, then seal
   it interactively:

   ```sh
   nix develop --command bash addrspace/scripts/clickstack-seal-secret.sh mcp
   ```

   The helper prompts without echo, seals `clickstack-mcp-credentials` in
   `nexus`, and writes only ciphertext to
   `addrspace/apps/nexus/clickstack-mcp-credentials.sealed.yaml`. Add it to
   `addrspace/apps/nexus/kustomization.yaml`. Once Flux creates the Secret, the
   replacement Nexus pod starts and the apps health check can pass.

The API key is not an OTel ingestion token. This workspace has no cluster
context, so the helper cannot fetch the public certificate here and live
bootstrap has not been performed. Keep the PR draft until both encrypted
credentials exist and OTLP ingestion, UI access, MCP tools, and Nexus's tool
catalog are verified.

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
releases.

After verifying the HyperDX UI, OTLP logs/traces/metrics, and Nexus MCP tools,
run the retirement helper first in plan mode:

```sh
nix develop --command bash addrspace/scripts/retire-observability-legacy.sh --plan
```

It scopes its plan to seven K3s HelmCharts in `kube-system`, the two
repository-owned PrometheusRules, five ServiceMonitors, and four Probes. Apply
mode rechecks ClickStack app/collector readiness and requires the interactive
confirmation `RETIRE-VERIFIED-CLICKSTACK`; it deletes those exact CR instances,
then deletes the named HelmChart objects so K3s helm-controller performs each
release uninstall. It does not run `helm uninstall` or change Flux pruning. It
then inventories every remaining `monitoring.coreos.com` resource. Only if the
cluster-wide inventory is empty does it offer a second confirmation to remove
the ten CRDs shipped by kube-prometheus-stack `88.2.0`; any remaining CR instance
causes it to retain all CRDs. PVCs, PVs, and ZFS datasets are never deletion
targets.

The helper intentionally leaves the old Grafana OIDC sealed secrets and
TinyAuth client configuration. Remove their Deployment environment references
and sealed manifests in a separate Git change after confirming Grafana is
retired; deleting the Secret first would break TinyAuth's required references.
