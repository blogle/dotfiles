# Kubernetes Storage Migration

This is the nandstorm migration plan from k3s `local-path` to OpenEBS ZFS
LocalPV. It is deliberately split into declarative preparation and a later
maintenance-window migration. The old local-path PVCs, PVs, and backing data
must remain intact until a separate cleanup task is authorized.

## Resulting architecture

- OpenEBS ZFS LocalPV `v2.11.0` is installed by the existing k3s `HelmChart`
  mechanism in namespace `openebs`.
- NixOS creates `rpool/safe/kubernetes` as a `canmount=off` parent dataset.
  OpenEBS creates child datasets there, outside `/var/lib/rancher/k3s`.
- `openebs-zfspv` is the default, thin-provisioned native-ZFS StorageClass.
  It uses `WaitForFirstConsumer`, `refquota`, `allowVolumeExpansion`, lz4,
  128 KiB recordsize, disabled atime, and disabled deduplication.
- `openebs-zfspv-retain` has the same properties with `Retain` reclaim policy
  and is the preferred target for important application state.
- CSI VolumeSnapshot CRDs and the OpenEBS snapshot controller are enabled.
- `/persist/knowledge/vaults`, `/media`, and other explicit host datasets remain
  shared/canonical data and are not candidates for blind PVC conversion.

`openebs-zfspv` is now the default StorageClass. The k3s `local-storage` addon
and `local-path` StorageClass are disabled. The old local-path PVCs/PVs remain
bound with `Retain` reclaim policy for rollback. Do not change their
`storageClassName` fields in place.

## Current inventory

The live cluster inventory was captured on 2026-08-31 and source usage was
measured on nandstorm before cutover. The source local-path tree occupied 5.0G
in total; logical file sizes are recorded below because filesystem allocation
differs between local-path and compressed ZFS datasets.

| Namespace | Workload | Current storage | Purpose | Approx size | Target | Migration | Validation | Rollback |
| --- | --- | --- | --- | ---: | --- | --- | --- | --- |
| knowledge | markdown-vault-mcp | local-path, 10Gi | Rebuildable index/state | 880,362,765 logical bytes / 77,134 files | `markdown-vault-mcp-state-zfs` | Stopped Deployment; read-only source; metadata-preserving rsync | Reindex, health socket, SQLite integrity `ok`, pod recreation | Restore old claim reference |
| knowledge | ignis | local-path, 5Gi | Application state | Empty / 0 files | `ignis-data-zfs` | Stopped Deployment; read-only source; metadata-preserving rsync | Existing vaults loaded, HTTP 200, pod recreation | Restore old claim reference |
| knowledge | ignis | local-path, 5Gi | Obsidian web assets cache | 23,968,823 logical bytes / 352 files | `ignis-obsidian-app-zfs` | Stopped Deployment; read-only source; metadata-preserving rsync | Assets installed and HTTP 200, pod recreation | Restore old claim reference |
| knowledge | telegram-collector | local-path, 10Gi | SQLite/session/archive state | 28,843,205 logical bytes / 73 files | `telegram-collector-state-zfs` | Suspended auth job; stopped Deployment; read-only source; metadata-preserving rsync | Session/state present, pod recreation; auth remains suspended | Restore old claim reference |
| knowledge | chatgpt-collector | local-path, 10Gi | Exporter state/manifests | 715,498,818 logical bytes / 2,388 files | `chatgpt-collector-state-zfs` | Suspended CronJob; read-only source; metadata-preserving rsync | Manifest/state copy verified; CronJob remains suspended | Restore old claim reference |
| observability | Grafana | local-path, 2Gi | Dashboards/config/plugin state | 49,317,595 logical bytes / 543 files | `grafana-zfs` | Stopped Deployment; read-only source; metadata-preserving rsync | DB integrity `ok`, API health, pod recreation; datasource UIDs preserved | Restore old claim reference |
| observability | Prometheus | local-path, 16Gi | TSDB | 6,922,377,068 logical bytes / 79 files | `prometheus-zfs-prometheus-kube-prometheus-stack-prometheus-0` | Stopped operator replica; read-only source; metadata-preserving rsync | Healthy blocks/WAL replay, TSDB API, pod recreation | Restore old claim reference |
| observability | Loki | local-path, 20Gi | Log chunks/index | 8,901,228 logical bytes / 127 files | `loki-zfs` | Stopped StatefulSet and Alloy; source protected; read-only source; metadata-preserving rsync | Historical query, startup/WAL recovery, new query, pod recreation | Restore old claim reference |
| observability | Tempo | local-path, 10Gi | Trace blocks/WAL | 215 logical bytes / 1 file | `tempo-zfs` | Stopped StatefulSet and Alloy; read-only source; metadata-preserving rsync | Ready endpoint, startup recovery, pod recreation | Restore old claim reference |
| observability | Alertmanager | local-path, 1Gi | Alert state/silences | 0 logical bytes / 2 files | `alertmanager-zfs-alertmanager-kube-prometheus-stack-alertmanager-0` | Stopped operator replica; read-only source; metadata-preserving rsync | Ready endpoint, startup, pod recreation | Restore old claim reference |
| openhands | OpenHands | hostPath, 20Gi | Settings, conversations, workspace | 20Gi request | Explicit host dataset for now | Do not convert during this migration | Existing hostPath validation | Existing hostPath remains |

The following are explicitly retained host/ZFS datasets or static PVs, not
local-path migration targets: knowledge vaults, `/media` and `/media/downloads`,
Ollama model storage, media application configuration, Penpot state, Bitmagnet
state, Dojo state, and other named `/persist/...` PVs. Reclassify only with an
application-specific plan.

## Before production migration

Run as root on nandstorm and record the output. The source paths must not be
modified by these commands:

```sh
zpool status
zpool list
zfs list -o name,used,avail,refer,mountpoint,quota,refquota,compression
kubectl get sc,pv -o yaml > /persist/recovery/storage-pv-$(date -u +%Y%m%dT%H%M%SZ).yaml
kubectl get pvc --all-namespaces -o yaml > /persist/recovery/storage-pvc-$(date -u +%Y%m%dT%H%M%SZ).yaml
```

The source dataset was confirmed as `rpool/safe/persist`, with 570G pool free
and 269G available before migration. It was snapshotted before cutover:

```sh
zfs snapshot rpool/safe/persist@before-openebs-migration-20260831T234429Z
```

Local-path backing directories were under
`/persist/var/lib/rancher/k3s/storage/`. The snapshot remains retained.

## Disposable CSI validation

After applying the infrastructure overlay and confirming the OpenEBS pods,
run `OPENEBS_STORAGE_SMOKE_CONFIRM=1 ./hosts/nandstorm/k8s/infrastructure/storage-smoke.sh`. The explicit confirmation is required because the
test creates and deletes Kubernetes resources. It provisions a
disposable volume, writes a sentinel, recreates its pod, expands the volume,
creates a CSI snapshot, restores it into a second volume, and verifies the
sentinel. The script deletes the `storage-smoke` namespace on exit; because the
test StorageClass has `Delete` reclaim policy, its test datasets are removed.

For manual inspection or troubleshooting, the equivalent expansion and
snapshot steps are:

```sh
kubectl -n storage-smoke patch pvc zfs-smoke --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl -n storage-smoke wait --for=jsonpath='{.status.capacity.storage}'=2Gi \
  pvc/zfs-smoke --timeout=10m
kubectl -n storage-smoke apply -f - <<'YAML'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: zfs-smoke-snapshot
spec:
  volumeSnapshotClassName: zfs-snapshotclass
  source:
    persistentVolumeClaimName: zfs-smoke
YAML
kubectl -n storage-smoke wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/zfs-smoke-snapshot --timeout=10m
```

The exact generated `VolumeSnapshotClass` name must be checked with
`kubectl get volumesnapshotclass`. Confirm the corresponding `ZFSVolume` and
child dataset on nandstorm. A failed lifecycle test blocks production
migration.

The guarded smoke test passed on 2026-09-01 with the following command:

```sh
OPENEBS_STORAGE_SMOKE_CONFIRM=1 OPENEBS_STORAGE_SMOKE_TIMEOUT_SECONDS=600 \
  ./hosts/nandstorm/k8s/infrastructure/storage-smoke.sh
```

## Workload migration procedure

For each row, first capture the workload and PVC YAML, actual source path,
file count, apparent bytes, ownership, permissions, and application health.
Stop every writer before the final copy. Use a temporary migration pod with old
and new PVCs, or a host-side controlled copy, and preserve metadata:

```sh
rsync -aHAX --numeric-ids --delete /source/ /destination/
```

Validate file counts, byte totals, ownership, permissions, and checksums where
practical. For SQLite/Postgres/TSDB/WAL data, use the application's integrity
checks after a clean stop; a successful live `rsync` is not a consistent
database backup. Only then change the owning Kustomize/Helm declaration to a
new ZFS PVC, start the workload, test historical data and a new write, and
delete/recreate the pod to prove persistence.

Every old local-path PVC/PV and backing directory stays present and untouched.
Rollback means stopping the migrated workload, restoring its previous storage
reference, and starting it against the original source.

## Completed cutover

All ten rows are migrated, validated, and reboot-tested. `local-path` is
disabled in `hosts/nandstorm/kube.nix` with `--disable local-storage`. The old
PVCs, PVs, and data remain intentionally retained after cutover.

The active OpenEBS ZFS datasets are children of `rpool/safe/kubernetes` and
use lz4, `atime=off`, `logbias=throughput`, `refquota`, and the requested PVC
capacities. The final ZFS pool has approximately 240G available.

The old rollback sources intentionally retained are:

| Old PVC | Old PV | Source path | Logical size |
| --- | --- | --- | ---: |
| `knowledge/markdown-vault-mcp-state` | `pvc-414d82aa-19c9-4904-b509-e8efa722bafe` | `/persist/var/lib/rancher/k3s/storage/pvc-414d82aa-19c9-4904-b509-e8efa722bafe_knowledge_markdown-vault-mcp-state` | 880,362,765 bytes |
| `knowledge/ignis-data` | `pvc-90d52337-4a45-4347-9086-7095da61bd1a` | `/persist/var/lib/rancher/k3s/storage/pvc-90d52337-4a45-4347-9086-7095da61bd1a_knowledge_ignis-data` | 0 bytes |
| `knowledge/ignis-obsidian-app` | `pvc-51b292f0-8daa-4e3f-881a-f552b96adf5a` | `/persist/var/lib/rancher/k3s/storage/pvc-51b292f0-8daa-4e3f-881a-f552b96adf5a_knowledge_ignis-obsidian-app` | 23,968,823 bytes |
| `knowledge/telegram-collector-state` | `pvc-c87dc25e-a4da-4edc-be9b-845b722b2d5f` | `/persist/var/lib/rancher/k3s/storage/pvc-c87dc25e-a4da-4edc-be9b-845b722b2d5f_knowledge_telegram-collector-state` | 28,843,205 bytes |
| `knowledge/chatgpt-collector-state` | `pvc-6d067e51-a5d9-482a-ba49-9296cfcf46d7` | `/persist/var/lib/rancher/k3s/storage/pvc-6d067e51-a5d9-482a-ba49-9296cfcf46d7_knowledge_chatgpt-collector-state` | 715,498,818 bytes |
| `observability/grafana` | `pvc-852bad53-9582-4ee5-b980-64c053eb1c8e` | `/persist/var/lib/rancher/k3s/storage/pvc-852bad53-9582-4ee5-b980-64c053eb1c8e_observability_grafana` | 49,317,595 bytes |
| `observability/storage-loki-0` | `pvc-3156d8d3-7a7d-4e82-abd1-806296a5470c` | `/persist/var/lib/rancher/k3s/storage/pvc-3156d8d3-7a7d-4e82-abd1-806296a5470c_observability_storage-loki-0` | 8,901,228 bytes |
| `observability/storage-tempo-0` | `pvc-6e1e867d-deae-4f44-bad8-d198bb80f80e` | `/persist/var/lib/rancher/k3s/storage/pvc-6e1e867d-deae-4f44-bad8-d198bb80f80e_observability_storage-tempo-0` | 215 bytes |
| `observability/prometheus-...-0` | `pvc-632c0d00-915c-406e-8841-e92ea389c3cb` | `/persist/var/lib/rancher/k3s/storage/pvc-632c0d00-915c-406e-8841-e92ea389c3cb_observability_prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0` | 6,922,377,068 bytes |
| `observability/alertmanager-...-0` | `pvc-c034295f-4314-4c4a-a447-e7dcad580978` | `/persist/var/lib/rancher/k3s/storage/pvc-c034295f-4314-4c4a-a447-e7dcad580978_observability_alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0` | 0 bytes |

## Cleanup boundary

Deleting old local-path storage is a separate authorized task. It requires a
fresh backup, explicit confirmation that every replacement is healthy, and a
documented deletion list. CSI/ZFS snapshots on nandstorm are snapshots, not
off-host disaster-recovery backups.
