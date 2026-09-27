# addrspace Kubernetes cluster

## Purpose and ownership

The cluster is named `addrspace`; `nandstorm` is its current k3s host/node.
Host operating-system and node configuration belongs under `hosts/`. Kubernetes
desired state belongs under `addrspace/`.

## Repository layout

```text
addrspace/
├── controllers/     # CRD and controller providers
├── infrastructure/  # cluster configuration requiring those providers
├── platform/        # shared services and observability
├── apps/            # application workloads and their secrets
├── clusters/        # intended future Flux cluster entrypoint
├── scripts/
└── README.md
```

This file is the cluster operations and bootstrap runbook. Application-specific
operational contracts remain alongside their applications.

## Operate the established cluster

Flux is not bootstrapped. The top-level Kustomization aggregates all four layers
(`controllers`, `infrastructure`, `platform`, `apps`) for convenience on an
already-established cluster. Review and apply from the repository root:

```sh
kubectl diff -k addrspace
kubectl apply -k addrspace
```

Once Flux is bootstrapped, normal deployment should be commit/merge to Git and
Flux reconciliation. Direct `kubectl apply` should then be limited to
break-glass or debugging.

## Reconstruct a fresh cluster

The aggregate apply above is not a fresh-cluster bootstrap procedure. Kustomize
orders objects but does not wait for asynchronously installed CRDs or controller
readiness. Restore/build `nandstorm` first and confirm k3s is healthy, then apply
the layers in stages:

1. If rebuilding under the current transitional secret model, restore the
   historical Sealed Secrets keyring (recovery steps below).
2. Apply the controller providers:

   ```sh
   kubectl apply -k addrspace/controllers
   ```

3. Wait for controller deployments and their required CRDs to become ready.
   In particular, confirm Sealed Secrets, cert-manager, MetalLB, OpenEBS, and
   the Prometheus Operator are ready before proceeding.
4. Apply infrastructure:

   ```sh
   kubectl apply -k addrspace/infrastructure
   ```

5. Verify the `ClusterIssuer`, MetalLB address configuration, OpenEBS
   `StorageClass` and snapshot class, and that SealedSecrets decrypt into their
   target Secrets.
6. Apply platform services:

   ```sh
   kubectl apply -k addrspace/platform
   ```

7. Wait for platform services and operators to become healthy, then apply apps:

   ```sh
   kubectl apply -k addrspace/apps
   ```

8. Validate cluster health, workloads, claims, certificates, and external
   service addresses.

The readiness boundaries are intentional: the Sealed Secrets controller must
precede SealedSecret resources; cert-manager and its CRDs precede `ClusterIssuer`
`L2Advertisement`; OpenEBS and its CSI/CRDs precede StorageClasses and PVC
consumers; and Prometheus Operator CRDs precede `PrometheusRule`, `Probe`, and
`ServiceMonitor` resources. The OpenEBS chart installs its ZFS and snapshot
support. The controller layer already declares these providers. Do not apply
later layers until the corresponding provider is ready.

## Storage

Mutable Kubernetes application state uses OpenEBS ZFS LocalPV. Persistent claims
should normally use the appropriate `openebs-zfspv` or
`openebs-zfspv-retain` StorageClass. `/media` and `/persist/knowledge` vault
data are intentional direct hostPath-backed exceptions. The completed
`local-path` PVC migration sources have been retired and must not be reintroduced.

## Secrets

Application secrets are committed as SealedSecrets. The historical Sealed
Secrets controller keyring has an agenix-encrypted, point-in-time disaster-
recovery backup in `secrets/addrspace-sealed-secrets-keyring.age`. It exists only
to reconstruct the current cluster during the transition and is not a routine
deployment artifact. This does not establish an operational process for
periodically backing up controller-generated sealing keys; key rotation remains
enabled. This backup is deliberately transitional and should eventually
disappear. The immediate next secrets/bootstrap iteration should provision the
cryptographic root of trust through GitOps before Sealed Secrets starts, rather
than exporting a root from an already-running controller.

For emergency recovery only, decrypt to a restricted temporary file and apply
that file without displaying its contents:

```sh
set -e
umask 077
tmp=$(mktemp)
trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT
agenix -d secrets/addrspace-sealed-secrets-keyring.age > "$tmp"
chmod 600 "$tmp"
kubectl apply -f "$tmp"
```

Keep the temporary file on a protected filesystem and remove it immediately.
This manual recovery path is temporary and should be replaced by the upcoming
GitOps-provisioned root of trust.

## Dependency boundaries

The future reconciliation order is:

```text
controllers → infrastructure → platform → apps
```

CRDs must be established by healthy controllers before custom resources are
reconciled. The staged bootstrap above describes the readiness checks; preserve
those dependencies when defining Flux health checks. Application SealedSecrets
remain with their applications and depend on the Sealed Secrets controller.

## Agent Sandbox

Anvil vendors the exact upstream Agent Sandbox v1.0.2 release manifest at Anvil
commit `13334d5709a6a9f1f1c8894da33b8ef09565a3df`; its base intentionally does
not install the controller. `addrspace/controllers/agent-sandbox` declares that
pinned platform dependency and owns its installation. Anvil workloads consume
Agent Sandbox but do not own its lifecycle.

## Flux status

```text
Flux-ready structure: yes
Flux bootstrapped: no
```

`addrspace/clusters/addrspace` is the intended future Flux entrypoint. No Flux
controllers or reconciliation resources are currently present.
