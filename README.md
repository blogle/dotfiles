# dotfiles

This repository contains the NixOS configurations for the machines **modulus** and **nandstorm**.

## k3s on `nandstorm`

The headless server `nandstorm` runs a single-node k3s cluster.  The service state is persisted under `/persist` so it survives reboots.

### Getting access from `modulus`

1. Copy `/etc/rancher/k3s/k3s.yaml` from `nandstorm` to
   `~/.kube/nandstorm.yaml` on `modulus`.
2. Edit the copied file and replace the server IP with `10.0.0.26`.
3. Export `KUBECONFIG=$HOME/.kube/nandstorm.yaml` for daily work.

After this `kubectl` will talk to the cluster running on `nandstorm`.

## Kustomize manifests

The `addrspace/` directory contains the Kubernetes desired state for the
`addrspace` cluster and is organized as a [Kustomize](https://kustomize.io/)
configuration. Flux has not been bootstrapped; the current manual workflow is:

```sh
kubectl diff -k addrspace
kubectl apply -k addrspace
```

See [`addrspace/README.md`](addrspace/README.md) for cluster ownership, storage,
secret handling, dependency layers, and recovery guidance.

### Networking requirements

The server must load the `br_netfilter` and `overlay` kernel modules,
enable bridge firewalling and allow IPv4 forwarding so the bundled flannel CNI
works correctly.  This is handled in `hosts/nandstorm/default.nix` but is worth
noting when porting the configuration to other machines.

## Deploying NixOS changes

Remote hosts (like `nandstorm`) are deployed via [deploy-rs](https://github.com/serokell/deploy-rs):

```sh
deploy .#nandstorm
```

This builds the NixOS closure locally and activates it on the remote host over SSH.
Use `deploy` instead of `sudo nixos-rebuild switch` for remote machines —
`nixos-rebuild` requires root on the target and is intended for local use only.

To check what would change without applying:

```sh
deploy .#nandstorm --dry-activate
```
