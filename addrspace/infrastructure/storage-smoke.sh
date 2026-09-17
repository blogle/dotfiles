#!/usr/bin/env bash
set -euo pipefail

namespace=storage-smoke
manifest="$(dirname "$0")/storage-smoke.yaml"

if [[ ${OPENEBS_STORAGE_SMOKE_CONFIRM:-} != 1 ]]; then
  echo "Refusing to run. Set OPENEBS_STORAGE_SMOKE_CONFIRM=1 explicitly." >&2
  exit 2
fi

timeout_seconds=${OPENEBS_STORAGE_SMOKE_TIMEOUT_SECONDS:-1200}
if [[ ! $timeout_seconds =~ ^[0-9]+$ ]] || (( timeout_seconds < 60 )); then
  echo "OPENEBS_STORAGE_SMOKE_TIMEOUT_SECONDS must be an integer of at least 60" >&2
  exit 2
fi

if [[ ${OPENEBS_STORAGE_SMOKE_INNER:-} != 1 ]]; then
  export OPENEBS_STORAGE_SMOKE_INNER=1
  exec timeout --foreground --signal=TERM --kill-after=30s "${timeout_seconds}s" "$0"
fi

deadline=$((SECONDS + timeout_seconds))
kube() {
  if (( SECONDS >= deadline )); then
    echo "Storage smoke test exceeded its time budget" >&2
    return 124
  fi
  kubectl --request-timeout=30s "$@"
}

read -r snapshot_class < <(kube get volumesnapshotclass -o jsonpath='{range .items[?(@.driver=="zfs.csi.openebs.io")]}{.metadata.name}{"\n"}{end}')

if [[ -z "$snapshot_class" ]]; then
  echo "No OpenEBS ZFS VolumeSnapshotClass is available" >&2
  exit 1
fi

cleanup() {
  status=$?
  if (( status == 0 )); then
    kube delete namespace "$namespace" --ignore-not-found=true --wait=false --timeout=10s
  else
    echo "Smoke test failed; retaining $namespace for diagnosis." >&2
  fi
}
trap cleanup EXIT

kube apply -f "$manifest"
kube -n "$namespace" wait --for=condition=Ready pod/zfs-smoke --timeout=10m
kube -n "$namespace" exec zfs-smoke -- sh -c 'printf smoke-sentinel > /data/sentinel && sync'

kube -n "$namespace" patch pvc zfs-smoke --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kube -n "$namespace" wait --for=jsonpath='{.status.capacity.storage}'=2Gi \
  pvc/zfs-smoke --timeout=10m

kube -n "$namespace" apply -f - <<YAML
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: zfs-smoke-snapshot
spec:
  volumeSnapshotClassName: $snapshot_class
  source:
    persistentVolumeClaimName: zfs-smoke
YAML
kube -n "$namespace" wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/zfs-smoke-snapshot --timeout=10m

kube -n "$namespace" delete pod zfs-smoke --wait=false
kube -n "$namespace" wait --for=delete pod/zfs-smoke --timeout=2m
kube -n "$namespace" create -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: zfs-smoke
spec:
  containers:
    - name: smoke
      image: busybox:1.37.0
      command: ["sh", "-c", "test \"$(cat /data/sentinel)\" = smoke-sentinel && sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: zfs-smoke
YAML
kube -n "$namespace" wait --for=condition=Ready pod/zfs-smoke --timeout=10m
test "$(kube -n "$namespace" exec zfs-smoke -- cat /data/sentinel)" = smoke-sentinel

kube -n "$namespace" apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: zfs-smoke-restore
spec:
  storageClassName: openebs-zfspv
  dataSource:
    name: zfs-smoke-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: zfs-smoke-restore
spec:
  restartPolicy: Never
  containers:
    - name: verify
      image: busybox:1.37.0
      command: ["sh", "-c", "test \"$(cat /data/sentinel)\" = smoke-sentinel"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: zfs-smoke-restore
YAML
kube -n "$namespace" wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/zfs-smoke-restore --timeout=10m

echo "ZFS CSI provision, persistence, expansion, snapshot, and restore passed."
