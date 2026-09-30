#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bash addrspace/scripts/retire-observability-legacy.sh [--plan|--apply]

--plan (default) lists only the exact legacy HelmCharts and Prometheus Operator
CR instances this repository owned. --apply requires an interactive typed
confirmation and ready ClickStack app/collector, deletes those named CRs, then
deletes the seven named K3s HelmChart objects so helm-controller uninstalls the
releases. It never deletes CRDs, PVCs, PVs, ZFS datasets, or unrelated objects.
EOF
}

mode=${1:---plan}
case "$mode" in
  --plan|--apply) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

command -v kubectl >/dev/null 2>&1 || { printf 'kubectl is required; use nix develop.\n' >&2; exit 1; }
context=$(kubectl config current-context 2>/dev/null) || {
  printf 'No kubectl context. Select the addrspace cluster before running this tool.\n' >&2
  exit 1
}
[[ -n "$context" ]] || { printf 'No kubectl context is selected.\n' >&2; exit 1; }

charts=(kube-prometheus-stack grafana loki tempo alloy-logs alloy-otel blackbox-exporter)
prometheusrules=(
  'ai/ollama-alerts'
  'observability/observability-alerts'
)
servicemonitors=(
  'media/sonarr-exporter'
  'media/radarr-exporter'
  'media/prowlarr-exporter'
  'kube-system/dcgm-exporter'
  'observability/blackbox-exporter'
)
probes=(
  'observability/grafana-public'
  'observability/sonarr-public'
  'observability/tinyauth-public'
  'observability/tcp-check-observability-tempo'
)

print_existing() {
  local resource=$1 names=$2 entry namespace name
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    namespace=${entry%%/*}
    name=${entry#*/}
    kubectl get "$resource" "$name" -n "$namespace" -o name --ignore-not-found 2>/dev/null || true
  done <<< "$names"
}

print_monitoring_inventory() {
  local resource
  printf '\nAll current monitoring.coreos.com resources (inventory only):\n'
  while IFS= read -r resource; do
    [[ -n "$resource" ]] || continue
    printf '%s: ' "$resource"
    kubectl get "$resource" --all-namespaces -o name --ignore-not-found 2>/dev/null | tr '\n' ' '
    printf '\n'
  done < <(kubectl api-resources --api-group=monitoring.coreos.com --verbs=list -o name 2>/dev/null || true)
  printf 'Installed monitoring.coreos.com CRDs (inventory only):\n'
  kubectl get crd -o name | grep 'monitoring.coreos.com' || true
}

printf 'Cluster context: %s\n' "$context"
printf '\nExact legacy K3s HelmCharts in kube-system:\n'
for name in "${charts[@]}"; do
  kubectl get helmchart "$name" -n kube-system -o name --ignore-not-found 2>/dev/null || true
done
printf '\nRepository-owned PrometheusRules:\n'
print_existing prometheusrules "$(printf '%s\n' "${prometheusrules[@]}")"
printf '\nRepository-owned ServiceMonitors:\n'
print_existing servicemonitors "$(printf '%s\n' "${servicemonitors[@]}")"
printf '\nRepository-owned Probes:\n'
print_existing probes "$(printf '%s\n' "${probes[@]}")"
print_monitoring_inventory
printf '\nCRDs, PVCs, PVs, and ZFS datasets are not deletion targets.\n'

[[ "$mode" == --apply ]] || exit 0
[[ -t 0 ]] || { printf 'Refusing --apply without an interactive terminal.\n' >&2; exit 1; }

kubectl -n observability wait --for=condition=Available deployment/clickstack-app --timeout=2s >/dev/null || {
  printf 'ClickStack app is not Available; refusing legacy retirement.\n' >&2
  exit 1
}
desired=$(kubectl -n observability get daemonset clickstack-otel-collector-agent -o jsonpath='{.status.desiredNumberScheduled}')
ready=$(kubectl -n observability get daemonset clickstack-otel-collector-agent -o jsonpath='{.status.numberReady}')
[[ "$desired" =~ ^[1-9][0-9]*$ && "$ready" == "$desired" ]] || {
  printf 'ClickStack collector is not ready on every eligible node (%s/%s); refusing legacy retirement.\n' "$ready" "$desired" >&2
  exit 1
}

printf '\nConfirm that ClickStack UI, OTLP traces/metrics/logs, and Nexus MCP have all passed live smoke tests.\n'
read -r -p 'Type RETIRE-VERIFIED-CLICKSTACK to continue: ' confirmation
[[ "$confirmation" == RETIRE-VERIFIED-CLICKSTACK ]] || { printf 'Confirmation did not match; no resources changed.\n' >&2; exit 1; }

for entry in "${prometheusrules[@]}"; do
  kubectl delete prometheusrule "${entry#*/}" -n "${entry%%/*}" --ignore-not-found --wait=true
done
for entry in "${servicemonitors[@]}"; do
  kubectl delete servicemonitor "${entry#*/}" -n "${entry%%/*}" --ignore-not-found --wait=true
done
for entry in "${probes[@]}"; do
  kubectl delete probe "${entry#*/}" -n "${entry%%/*}" --ignore-not-found --wait=true
done

for name in "${charts[@]}"; do
  if kubectl get helmchart "$name" -n kube-system -o name --ignore-not-found | grep -q .; then
    printf 'Requesting helm-controller uninstall for HelmChart %s/kube-system\n' "$name"
    kubectl delete helmchart "$name" -n kube-system --wait=true --timeout=20m
  fi
done

printf '\nPost-uninstall Prometheus Operator inventory (review before any CRD deletion):\n'
print_monitoring_inventory
printf '\nPVC/PV/ZFS data was not targeted. Remove Grafana TinyAuth client configuration and sealed OIDC material only in a separate reviewed Git change after confirming Grafana is retired.\n'
