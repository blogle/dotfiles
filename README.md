# dotfiles

This repository contains the NixOS configurations for the machines **modulus** and **nandstorm**.

## k3s on `nandstorm`

The headless server `nandstorm` runs a single-node k3s cluster.  The service
state is persisted under `/persist` so it survives reboots.

### Getting access from `modulus`

1. Copy `/etc/rancher/k3s/k3s.yaml` from `nandstorm` to
   `~/.kube/nandstorm.yaml` on `modulus`.
2. Edit the copied file and replace the server IP with `10.0.0.26`.
3. Export `KUBECONFIG=$HOME/.kube/nandstorm.yaml` for daily work.

After this `kubectl` will talk to the cluster running on `nandstorm`.

## Kubernetes manifests

The `hosts/nandstorm/k8s` directory contains manifests for cluster
infrastructure and all former docker-compose services.  Apply them with:

```sh
kubectl apply -f hosts/nandstorm/k8s/infrastructure
kubectl apply -f hosts/nandstorm/k8s/apps
```

This installs MetalLB, ExternalDNS, the NVIDIA device plugin and exposes
Jellyfin, Transmission and friends via Traefik with TLS.
