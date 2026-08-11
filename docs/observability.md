# Observability stack — operational documentation

The observability stack ships Prometheus (metrics), Loki (logs), Tempo
(traces), Grafana (single-pane UI), Grafana Alloy (collector), and
blackbox-exporter (synthetic probes) into the `observability` namespace
of the nandstorm k3s cluster. Manifests live in
`hosts/nandstorm/k8s/infrastructure/observability/` and follow the repo's
existing conventions: Rancher `HelmChart` CRDs declared in the
`kube-system` namespace with `targetNamespace: observability` (same pattern
as `cert-manager.yaml`, `external-dns.yaml`, `keel.yaml`), Traefik +
`letsencrypt` ClusterIssuer for public TLS, and tinyauth forward-auth SSO
at the Grafana ingress.

This document records endpoints, retention, the storage budget, kubelet
log rotation, and how applications opt in to metrics and tracing.

## Endpoints

| Component            | Internal (`*.svc.cluster.local`)             | Public                                       |
|----------------------|----------------------------------------------|----------------------------------------------|
| Grafana UI           | `grafana.observability.svc:80`               | https://grafana.thejeffer.net                |
| Prometheus           | `kube-prometheus-stack-prometheus.observability.svc:9090`  | none (ClusterIP)                 |
| Alertmanager         | `kube-prometheus-stack-alertmanager.observability.svc:9093` | none (ClusterIP)                 |
| Loki (gateway)       | `loki-gateway.observability.svc:80`          | none (ClusterIP)                             |
| Tempo (Query/UI)     | `tempo.observability.svc:3200`              | none (ClusterIP)                             |
| Tempo OTLP receive   | `tempo.observability.svc:4317` (gRPC), `:4318` (HTTP) — apps DO NOT push here directly | — |
| Alloy OTLP gateway   | `alloy-otel.observability.svc:4317` (gRPC), `:4318` (HTTP), `:12345` (Alloy metrics) | — |
| Alloy logs collector | DaemonSet on every node, no Service          | —                                            |
| blackbox-exporter    | `prometheus-blackbox-exporter.observability.svc:9115` | —                                    |

Apps push their telemetry to the **Alloy OTLP gateway**, never directly to
Tempo or Loki. See "How applications opt in" below.

## Datasources (Grafana)

Provisioned declaratively in `infrastructure/observability/grafana.yaml`:

* Prometheus — `http://kube-prometheus-stack-prometheus.observability.svc:9090` (default)
* Loki — `http://loki-gateway.observability.svc`
* Tempo — `http://tempo.observability.svc:3200` (Trace-to-Logs v2 linked to Loki)

Edits belong in the `datasources:` block of `grafana.yaml`, not in the UI;
the chart rewrites the provisioning ConfigMap on every release upgrade.

## Grafana authentication

Grafana is exposed publicly through Traefik + the `letsencrypt` Cluster
Issuer and is gated by the same tinyauth forward-auth middlewares used by
sonarr/radarr/opencode (annotations on the Grafana `Ingress`). Anonymous
access is disabled (`auth.anonymous.enabled: false` in `grafana.ini`).
The chart-generated admin password is stored in the `grafana` Secret:

```sh
kubectl -n observability get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

Rotate via the Grafana web UI (after first SSO-gated login) or by editing
the Secret directly.

## Sampling policy (tempo)

Tempo stores traces for **72 hours only** as a bounded cache. To avoid
filling the 10Gi PVC the collector applies tail sampling:

* up to 8% probabilistic sample of healthy traces,
* health-check traces (`http.route` of `/healthz`, `/readyz`, `/live`,
  `/ready`, `/ping`, `/metrics`) are dropped via a `string_attribute` policy,
* Tempo additionally drops any trace exceeding `max_bytes_per_trace = 2MiB`.

**Follow-up (intentional, per spec):** the spec's "100% of error traces"
(`status_code` policy) and "100% of slow traces" (`latency` policy) tail
sampling is left as a documented next step. The probabilistic 5–10% floor
is already implemented so the storage cannot run away silently; the
error/slow guarantees are additive and can be added without changing the
gateway's structural shape.

## Retention & storage budget

The observability namespace has a `ResourceQuota` of **64Gi of
PersistentVolumeClaims** and **8 PVCs** total. The actual PVC plan matches
the spec's sized-cache plan:

| Component   | PVC size | Retention |
|-------------|----------|-----------|
| Prometheus  | 16Gi     | 10d, size-based 12GiB |
| Loki        | 20Gi     | 7d (168h)             |
| Tempo       | 10Gi     | 72h                   |
| Grafana     | 2Gi      | unlimited (config/dashboard state) |
| Alertmanager| 1Gi      | n/a (state is transient) |

Sum = 49Gi; headroom = 15Gi for WAL, compaction, and filesystem overhead.
The 12GiB Prometheus size-based retention deliberately stays below the 16Gi
PVC size for the same reason: WAL + compaction still need a few GiB of
working space. The ResourceQuota stops a runaway chart bump (or forgotten
retention knob) from silently blowing past the budget.

### Storage class & impermanence

Helm-managed PVCs use the k3s built-in **`local-path`** StorageClass, which
writes data under `/var/lib/rancher/k3s/storage`. `/var/lib/rancher` is
persisted via impermanence (`environment.persistence."/persist".directories`
in `hosts/nandstorm/default.nix`), so observability state survives reboots
without any per-component hostPath wiring. The static-PV-under-`/persist`
pattern used by the media apps would also work but adds unnecessary
plumbing for Helm-managed stateful workloads.

### Kubelet container-log rotation

Node-local container logs are bounded at the kubelet before they are
collected by Loki. Set in `hosts/nandstorm/kube.nix` via k3s
`extraFlags`:

```nix
"--kubelet-arg=container-log-max-size=5Mi"
"--kubelet-arg=container-log-max-files=3"
```

This caps each container at ~15MiB of node-local logs (5MiB max file × 3
files). A k3s restart (`systemctl restart k3s`) is required to pick these
up. The Alloy logs DaemonSet tails from `/var/log/pods`, applies the
drop filters enumerated below in "Log drop policy", then forwards to the
Loki gateway.

Loki runs in single-tenant mode with `auth_enabled: false`. Alloy and Grafana
therefore do not need an `X-Scope-OrgID`; enabling multi-tenancy requires
updating both clients at the same time.

### Loki ingestion limits

Set in `loki.limits_config` in `infrastructure/observability/loki.yaml`:

| knob                       | value          |
|----------------------------|----------------|
| `ingestion_rate_mb`        | 2              |
| `ingestion_burst_size_mb`  | 4              |
| `per_stream_rate_limit`    | 1MB            |
| `per_stream_rate_limit_burst` | 5MB         |
| `max_global_streams_per_user` | 5000        |
| `retention_period`         | 168h (7d)      |

### Tempo ingestion limits

Set in `tempo.limits` (chart) / mirrored to Tempo's config in
`infrastructure/observability/tempo.yaml`:

| knob                  | value       |
|-----------------------|-------------|
| `ingestion_rate_mb`   | 1           |
| `ingestion_burst_size_mb` | 4       |
| `max_bytes_per_trace` | 2097152 (2MiB) |

## Log label namespaces (low-cardinality discipline)

Loki labels are kept **low-cardinality**. The Alloy log collector only
extracts these as Loki labels:

```
cluster   namespace   pod   node   app   container   level
```

Pod and node are labels because infrastructure dashboards must pivot directly
to a workload instance. Everything else (`trace_id`, `request_id`, `user_id`,
`ip`, `path`, `session_id`, ...) MUST stay in structured log fields. The Loki
`max_global_streams_per_user` cap and `max_label_names_per_series: 30` provide
a hard backstop.

## Log drop policy (Alloy logs DaemonSet)

The alloy-logs DaemonSet (in `alloy.yaml`) drops the spec's listed
low-value streams before they hit Loki:

* Kubernetes readiness/liveness probe noise — `stage.drop` on the
  CRI lines `(GET|HEAD) /(healthz|readyz|health|ready|livez)/?`.
* Routine health-check request lines on app servers — `(GET|HEAD)
  /(metrics|ping)/?`.
* Excessively long single log lines — drops lines of 1,000 or more characters.
* Debug/trace log lines from the observability stack talking to itself,
  where `namespace="observability"` and the line matches `-(DEBUG|TRACE)-`.

Real application debug logs are NOT dropped (this filter is namespace- +
level-scoped). Tune the `drop_noise` `loki.process` block if you need to
add per-app drops.

## How applications opt in

### Prometheus metrics (self-hosted services, exporters)

Drop a `ServiceMonitor` (or `PodMonitor`) in the workloads's own
namespace. Prometheus is configured with an **empty match-all**
`serviceMonitorSelector`/`podMonitorSelector`/`ruleSelector`/`probeSelector`,
so it picks up monitors from any namespace — no label-namespace bookkeeping
is needed.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: myapp-ns
spec:
  selector:
    matchLabels: { app: myapp }
  namespaceSelector:
    matchNames: [myapp-ns]
  endpoints:
    - port: http
      interval: 30s         # or 60s for low-value, 15s for critical
      path: /metrics
```

Use the scrape cadence the spec defines:

* **15s** `criticalInfraScrapeInterval` — kubelet, kube-state-metrics,
  node-exporter, alert-critical core services.
* **30s** `defaultScrapeInterval` — anything without an explicit cadence.
* **60s** `lowValueServiceScrapeInterval` — media-stack exporters and other
  non-critical app scrapes (the `apps/media/exportarr.yaml` ServiceMonitors
  use 60s for this reason).

The *arr exporters live in `apps/media/exportarr.yaml` as the canonical
worked example of an app-level opt-in. To add `Lidarr`/`Bazarr`/`SABnzbd`,
copy a `<app>-exporter` Deployment + Service + ServiceMonitor alongside
the existing Exportarr blocks.

> Each Exportarr Deployment reads its arr's API key from a Secret
> (`sonarr-exportarr-secrets`, `radarr-exportarr-secrets`,
> `prowlarr-exportarr-secrets` in the `media` namespace). The
> `secretKeyRef` is `optional: true` so the Deployments come up cleanly
> before the operator creates the Secret:

> ```sh
> kubectl -n media create secret generic sonarr-exportarr-secrets \
>   --from-literal=apikey="<ApiKey from /persist/sonarr/config.xml>"
> ```
> Repeat for `radarr` (port 7878) and `prowlarr` (port 9696).

### OpenTelemetry traces & logs

Personal projects send OTLP to the Alloy gateway, not to Tempo or Loki
directly:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy-otel.observability.svc.cluster.local:4317
OTEL_SERVICE_NAME=<service-name>
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=homelab
```

Use `:4317` for OTLP gRPC and `:4318` for OTLP HTTP. The gateway tailsamples (see "Sampling policy") and routes traces to Tempo (`tempo.observability.svc:4317`)
and logs to Loki (`loki-gateway.observability.svc` OTLP path
`/otlp/v1/logs`). **In-cluster app Prometheus metrics should still be
scraped by Prometheus**, not pushed here — the Alloy gateway intentionally
does NOT connect metrics to any backend; app metrics received at the OTLP
receiver are dropped at the receiver (a deliberate drop, not a silent failure).

### Application-level dashboards

Label a ConfigMap `grafana_dashboard: "1"` and put a `.json` dashboard key
inside. Grafana's sidecar sweeps **all namespaces** for that label and
imports/deletes dashboards automatically (`searchNamespace: ALL`).

### New alerts

Add `PrometheusRule` objects anywhere; Prometheus picks them up via the
match-all `ruleSelector`. The platform alerts (PVC pressure, target down,
Loki rejections, Tempo dropped spans, Alloy dropped telemetry, node not
ready, pod crash loops) live in `infrastructure/observability/alert-rules
.yaml`; add app-specific rules next to the apps they describe.

## Alertmanager / notifications

Alertmanager is deployed with **no notification receiver wired yet**. The
default receiver is `null`, so alerts are queryable only via the
Alertmanager UI (`kubectl -n observability port-forward svc/kube-prometheus-stack-alertmanager 9093`)
and through Grafana's `alerting` view. When you wire in a real channel
(Discord/Slack/SMTP), edit the `alertmanager.alertmanagerSpec` block of
`kube-prometheus-stack.yaml` and supply a secret-referenced
configuration template; the alerts themselves are already defined and will
fire as soon as the receiver exists.

## Validation on-cluster

After deploying:

```sh
kubectl -n observability get pods
kubectl -n observability get helmcharts -A | grep -E 'kube-prometheus|grafana|loki|tempo|alloy|blackbox'
kubectl -n observability get servicemonitors,probes,prometheusrules -A
```

Smoke-test a trace through the gateway:

```sh
# 1.otel-cli via port-forward (or in-cluster):
otel-cli span --endpoint grpc://alloy-otel.observability.svc.cluster.local:4317 \
  --name smoke --service test --kind client

# 2. In Grafana, Tempo datasource, "Search" tab: pick the smoke-test trace.
```

## Pinned chart versions & follow-up

Each HelmChart pins a `version:`. On upgrade, the relevant `VERIFY` block
at the top of each `*.yaml` file lists the value-keys the maintainer should
recheck against the chart's CHANGELOG. The Helm `valuesContent:` blocks are
opaque to `kubectl kustomize` so they cannot be validated until the
helm-controller renders them; keys that depend on chart documentation
(`loki.singleBinary` for v6, `tempo.limits` for v1, `alloy` chart
`controller` / `service.ports` shape) are explicitly flagged in comments.

The spec's documented follow-ups for this first cut:

* full error/slow tail sampling in `alloy-otel` (currently probabilistic
  sampling + health-check drop),
* a notification receiver for Alertmanager (currently `null`),
* `Lidarr`/`Bazarr`/`SABnzbd` Exportarr deployments if/when those apps
  are added to `apps/media/`.
