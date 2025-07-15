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

The `hosts/nandstorm/k8s` directory contains manifests for cluster
infrastructure and all former docker-compose services.  It is organized as a
[Kustomize](https://kustomize.io/) configuration.  Apply everything with:

```sh
kubectl apply -k hosts/nandstorm/k8s
```

`kubectl` includes built-in support for Kustomize, so no separate installation is
required.

This installs MetalLB, ExternalDNS, Traefik, the NVIDIA device plugin and
exposes Jellyfin, Transmission and friends via Traefik with TLS.  Traefik and
ExternalDNS require a Cloudflare API token which is managed with agenix and
loaded into the cluster by the `k8s-secret-cloudflare` service.

### Networking requirements

The server must load the `br_netfilter` and `overlay` kernel modules,
enable bridge firewalling and allow IPv4 forwarding so the bundled flannel CNI
works correctly.  This is handled in `hosts/nandstorm/default.nix` but is worth
noting when porting the configuration to other machines.
