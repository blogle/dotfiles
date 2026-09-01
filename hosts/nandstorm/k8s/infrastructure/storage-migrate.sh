#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${OPENEBS_STORAGE_MIGRATE_CONFIRM:-} != 1 ]]; then
  echo "Refusing to migrate. Set OPENEBS_STORAGE_MIGRATE_CONFIRM=1 explicitly." >&2
  exit 2
fi

if (( $# != 4 )); then
  echo "usage: $0 <namespace> <target-pvc> <source-host-path> <pod-name>" >&2
  exit 2
fi

namespace=$1
target_pvc=$2
source_path=$3
pod_name=$4
timeout_seconds=${OPENEBS_STORAGE_MIGRATE_TIMEOUT_SECONDS:-2700}

if [[ ! $timeout_seconds =~ ^[0-9]+$ ]] || (( timeout_seconds < 120 )); then
  echo "OPENEBS_STORAGE_MIGRATE_TIMEOUT_SECONDS must be an integer of at least 120" >&2
  exit 2
fi

if [[ $source_path != /var/lib/rancher/k3s/storage/* ]]; then
  echo "Refusing unexpected source path: $source_path" >&2
  exit 2
fi

if [[ ! $pod_name =~ ^[a-z0-9-]{1,40}$ ]]; then
  echo "Invalid migration pod name: $pod_name" >&2
  exit 2
fi

deadline=$((SECONDS + timeout_seconds))
kube() {
  if (( SECONDS >= deadline )); then
    echo "Migration exceeded its time budget" >&2
    return 124
  fi
  kubectl --request-timeout=30s "$@"
}

target_class=$(kube -n "$namespace" get pvc "$target_pvc" -o jsonpath='{.spec.storageClassName}')
target_status=$(kube -n "$namespace" get pvc "$target_pvc" -o jsonpath='{.status.phase}')
if [[ $target_class != openebs-zfspv && $target_class != openebs-zfspv-retain ]]; then
  echo "Refusing target PVC with unexpected StorageClass: $target_class" >&2
  exit 2
fi
if [[ $target_status != Bound && $target_status != Pending ]]; then
  echo "Target PVC has unexpected status: $target_status" >&2
  exit 2
fi

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

log "preflight namespace=$namespace target=$target_pvc source=$source_path"
kube apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
  labels:
    app.kubernetes.io/name: storage-migration
    app.kubernetes.io/component: copy
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 0
    runAsGroup: 0
  containers:
    - name: rsync
      image: alpine:3.22
      command: ["sh", "-c"]
      args:
        - |
          set -eu
          log() { printf '[%s] %s\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" "\$*"; }
          logical_bytes() { find "\$1" -xdev -type f -exec stat -c '%s' {} + | awk '{s+=\$1} END {print s+0}'; }
          trap 'rc=\$?; [ "\$rc" -eq 0 ] || log "ERROR rc=\$rc"; exit "\$rc"' EXIT
          log "installing rsync"
          apk add --no-cache rsync
          log "source mount: \$(findmnt -T /source -o SOURCE,FSTYPE,OPTIONS -n || true)"
          log "target mount: \$(findmnt -T /target -o SOURCE,FSTYPE,OPTIONS -n || true)"
          log "source permissions: \$(stat -c "%A %u:%g %n" /source)"
          log "target permissions: \$(stat -c "%A %u:%g %n" /target)"
          log "source logical-bytes/files before: \$(logical_bytes /source)/\$(find /source -xdev -type f | wc -l)"
          log "target logical-bytes/files before: \$(logical_bytes /target)/\$(find /target -xdev -type f | wc -l)"
          log "starting metadata-preserving copy"
          timeout 30m rsync -aHAX --numeric-ids --one-file-system --delete --info=progress2,stats2 /source/ /target/
          sync
          src_bytes=\$(logical_bytes /source)
          dst_bytes=\$(logical_bytes /target)
          src_files=\$(find /source -xdev -type f | wc -l)
          dst_files=\$(find /target -xdev -type f | wc -l)
          log "source bytes/files after: \$src_bytes/\$src_files"
          log "target bytes/files after: \$dst_bytes/\$dst_files"
          test "\$src_bytes" = "\$dst_bytes"
          test "\$src_files" = "\$dst_files"
          log "checking content and metadata with checksum dry-run"
          rsync -aHAXn --checksum --numeric-ids --one-file-system --delete --itemize-changes /source/ /target/
          log "copy and filesystem validation succeeded"
      volumeMounts:
        - name: source
          mountPath: /source
          readOnly: true
        - name: target
          mountPath: /target
  volumes:
    - name: source
      hostPath:
        path: $source_path
        type: Directory
    - name: target
      persistentVolumeClaim:
        claimName: $target_pvc
YAML

log "migration pod created; monitoring progress"
while :; do
  phase=$(kube -n "$namespace" get pod "$pod_name" -o jsonpath='{.status.phase}')
  log "pod phase=$phase"
  kube -n "$namespace" logs "$pod_name" --tail=8 2>/dev/null || true
  case "$phase" in
    Succeeded)
      log "migration succeeded; deleting completed pod without waiting for CSI teardown"
      kube -n "$namespace" delete pod "$pod_name" --wait=false
      exit 0
      ;;
    Failed)
      log "migration failed; retaining pod for diagnosis"
      kube -n "$namespace" describe pod "$pod_name" >&2 || true
      exit 1
      ;;
  esac
  sleep 15
done
