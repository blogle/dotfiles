# addrspace Kubernetes cluster

`addrspace` is the Kubernetes cluster hosted by the `nandstorm` k3s node.
Host operating-system configuration belongs under `hosts/`; Kubernetes desired
state belongs here. The cluster layers and Flux reconciliation order are:

```text
controllers → infrastructure → platform → apps
```

Flux Kustomizations point at those four existing directories; workload manifests
are not duplicated under `clusters/addrspace/`.

## Normal deployment

Edit Kubernetes desired state, open and merge a PR, and Flux reconciles `master`
automatically (source and layer intervals are one minute). Do not run
`kubectl apply -k addrspace` for routine deployment.

Renovate proposes Kubernetes/GitOps dependency updates as inspectable PRs. The
`Kubernetes desired state` required check validates manifests and policy; GitHub
auto-merge merges eligible Renovate PRs only after required checks pass and the
branch is current with `master`. Nix dependencies and host configuration remain
manually reviewed and deployed.

## Status and manual reconciliation

```sh
flux get sources git -A
flux get kustomizations -A
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization addrspace-controllers -n flux-system
flux reconcile kustomization addrspace-infrastructure -n flux-system
flux reconcile kustomization addrspace-platform -n flux-system
flux reconcile kustomization addrspace-apps -n flux-system
```

The reconciliation order is enforced with `dependsOn`. The controllers layer
waits for ready deployments/daemonsets and established provider CRDs, including
Sealed Secrets, cert-manager, MetalLB, OpenEBS ZFS LocalPV, and Agent Sandbox.
Infrastructure waits for its `ClusterIssuer` and
SealedSecrets to report Ready/Synced. Platform and apps wait on their upstream
layer. Kustomizations use targeted checks rather than `wait: true` for every
resource, since PVCs, jobs, suspended resources, and Rancher `HelmChart` objects
do not all represent provider readiness. Pruning remains disabled in every
layer. Removed observability HelmChart resources therefore require the documented
manual retirement procedure after the replacement is verified; this PR does not
change cluster-wide deletion behavior.

Direct `kubectl` changes are break-glass only. Flux is authoritative and may
revert a direct mutation at its next reconciliation. Commit the durable fix to
Git. Inspect any adoption or upgrade before proceeding:

```sh
kubectl kustomize addrspace >/tmp/addrspace.yaml
kubectl diff -k addrspace
```

## First Flux adoption / fresh bootstrap

The Sealed Secrets controller's cryptographic root is held outside Kubernetes
in the agenix-encrypted `secrets/addrspace-sealed-secrets-keyring.age` artifact.
NixOS decrypts it to the root-readable `/run/agenix` runtime path, then a
one-shot systemd unit waits for the k3s API and idempotently applies the exact
Secret objects using k3s's existing root kubeconfig. The decrypted manifest is
never stored in the Nix store or Git plaintext. Controller key renewal is
disabled (`--key-renew-period=0`); historical keys are retained and sealing-key
lifecycle is an intentional manual operation.

After this change is merged, activate the bootstrap prerequisite manually on
`nandstorm` using the repository's normal deployment command, for example:

```sh
sudo nixos-rebuild switch --flake .#nandstorm
```

Verify the 14 key Secret objects exist in `kube-system` without printing their
contents, then perform the one-time Flux adoption as root with the local k3s
kubeconfig. Apply the generated controller installation first so its CRDs exist,
then apply the sync resources; the sync's root Flux Kustomization will reconcile
the committed cluster entrypoint and all four layers:

```sh
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply \
  -f addrspace/clusters/addrspace/flux-system/gotk-components.yaml
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait \
  --for=condition=Established --timeout=2m \
  crd/gitrepositories.source.toolkit.fluxcd.io \
  crd/kustomizations.kustomize.toolkit.fluxcd.io
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply \
  -f addrspace/clusters/addrspace/flux-system/gotk-sync.yaml
```

Verify `flux-system` GitRepository Ready, then verify
`addrspace-controllers`, `addrspace-infrastructure`, `addrspace-platform`, and
`addrspace-apps` become Ready in order. Review reconciliation events and live
diffs for unexpected changes. Do not apply the aggregate `addrspace/` Kustomize
root during adoption; it is retained for static validation and deliberate
operator inspection, not normal deployment.

The public GitHub repository is read via unauthenticated HTTPS. Flux has no
GitHub credential and no write access. There is no public webhook receiver.

## Storage and dependency ownership

Persistent application state uses OpenEBS ZFS LocalPV (`openebs-zfspv` or
`openebs-zfspv-retain`). `/media` and `/persist/knowledge` are intentional
persisted hostPath exceptions. The retired `local-path` PVC migration sources
must not be reintroduced.

Anvil consumes Agent Sandbox; it does not own the provider. The controller layer
installs the exact upstream Agent Sandbox v1.0.2 manifest vendored at Anvil's
currently pinned commit. That vendor pin is maintained separately from Anvil's
deployable main revision.

## Application delivery policy

### Anvil: automatic delivery from passing main builds

Every successful Anvil `main` build publishes immutable `sha-<commit>` images
for both Anvil and its sandbox. One Renovate dependency advances the Kustomize
base and both image tags to that same commit. Kubernetes CI verifies both exact
GHCR artifacts exist; a passing, current Renovate PR can then automerge and
Flux deploys it. The vendor-provided Agent Sandbox controller pin remains a
separate dependency.

### Dojo staging: automatic delivery of semantic releases

Staging tracks Dojo semantic releases, not `master` HEAD. Commits which do not
produce a semantic release do not change staging. Each release produces a
`vX.Y.Z` Git tag and matching GHCR image; Renovate advances the staging base,
image version, and image digest together. CI verifies the release image matches
the pinned digest, then a passing, current Renovate PR can automerge and Flux
deploys staging. The mutable `staging` image tag and Keel polling are not used.

### Dojo production: operator-selected stable release

Production remains pinned to the operator-selected `v0.0.4` image and its
immutable digest, with the existing Kustomize base commit retained. Renovate
does not advance the Dojo production base or application image. A production
upgrade is an explicit human change through a normal PR, followed by CI, merge,
and Flux reconciliation.

## Nix deployment boundary

Kubernetes GitOps does not imply automated NixOS or Home Manager deployment.
GitHub Actions may run Nix checks/builds, but no action activates a host. Nix
flake inputs, host packages, and NixOS/Home Manager changes remain manually
reviewed and deployed. Renovate's Nix and GitHub Actions managers are not enabled.
