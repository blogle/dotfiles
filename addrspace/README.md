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

The top-level Kustomization aggregates every layer for the current manual
workflow. Application-specific operational contracts remain alongside each
application.

## Current operations

Flux is not bootstrapped. Review and apply the complete cluster from the
repository root:

```sh
kubectl diff -k addrspace
kubectl apply -k addrspace
```

After Flux is introduced, Git reconciliation is intended to become the normal
mutation path; direct `kubectl apply` should then be reserved for break-glass or
debugging operations.

## Storage

Mutable Kubernetes application state uses OpenEBS ZFS LocalPV. Persistent claims
should normally use the appropriate `openebs-zfspv` or
`openebs-zfspv-retain` StorageClass. `/media` and `/persist/knowledge` vault
data are intentional direct hostPath-backed exceptions. The completed
`local-path` PVC migration sources have been retired and must not be reintroduced.

## Secrets

Application secrets are committed as SealedSecrets. The historical Sealed
Secrets controller keyring has an agenix-encrypted disaster-recovery backup in
`secrets/addrspace-sealed-secrets-keyring.age`; it is not routinely deployed to
`nandstorm`. This is transitional protection. The intended long-term model is a
GitOps bootstrap-provisioned root of trust, so cluster reconstruction does not
depend on exporting controller-generated keys.

## Dependency boundaries

The future reconciliation order is:

```text
controllers → infrastructure → platform → apps
```

CRDs must be established by healthy controllers before custom resources are
reconciled. This includes Sealed Secrets before SealedSecrets, cert-manager
before `ClusterIssuer`, MetalLB before its address configuration, and OpenEBS
before its StorageClasses and volume claims. Application SealedSecrets remain
with their applications and depend on the Sealed Secrets controller. The
Prometheus Operator chart in `controllers/` provides CRDs used by platform
`PrometheusRule` and `Probe` resources; keep that readiness dependency explicit
when defining Flux health checks.

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
