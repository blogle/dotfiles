# addrspace Cluster

- Canonical cluster name: `addrspace`
- Repository: `blogle/dotfiles`
- Intended Flux cluster path: `addrspace/clusters/addrspace`
- Workload definitions: `addrspace/apps`
- Cluster and platform definitions: `addrspace/infrastructure`

The current deployment remains manual Kustomize from the repository root:

```sh
kubectl diff -k addrspace
kubectl apply -k addrspace
```

Flux is intentionally not bootstrapped by this refactor. The transitional root
Kustomization does not include this directory, so future Flux declarations can
coexist here without changing the current manual deployment path.

Before enabling Flux reconciliation, establish explicit dependency layers and
verify readiness between them:

- Controllers and their CRDs must exist before custom resources that depend on
  them.
- Infrastructure must become ready before applications that depend on it.
- Sealed Secrets controller availability must be established before relying on
  `SealedSecret` resources.
- cert-manager installation and cert-manager custom resources must not rely on
  accidental existing-cluster ordering.
- Storage and controller dependencies must be understood before enabling prune.

Those ordering and ownership checks are prerequisites for a future Flux change;
they are not solved by this preparation commit.
