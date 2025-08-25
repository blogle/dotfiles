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
ExternalDNS require a Cloudflare API key which is now managed via Sealed Secrets.
Use the helper script in `scripts/seal-secret.sh` to create encrypted manifests.

### Secrets with Sealed Secrets

We keep Kubernetes secrets encrypted in Git as SealedSecrets. The controller is
installed by `hosts/nandstorm/k8s/infrastructure/kustomization.yaml`.

Add or rotate a secret:

1. Generate the sealed manifest(s) locally (no plaintext committed):

   ./scripts/seal-secret.sh \
     --name cloudflare \
     -n cert-manager -n external-dns \
     --literal api-key=YOUR_CLOUDFLARE_API_KEY \
     --output-dir hosts/nandstorm/k8s/infrastructure \
     --scope cluster-wide

   This writes `cloudflare-cert-manager.sealed.yaml` and
   `cloudflare-external-dns.sealed.yaml` under the chosen `--output-dir`.

2. Reference the generated files in the appropriate `kustomization.yaml` under
   `resources` and apply:

   kubectl apply -k hosts/nandstorm/k8s/infrastructure

3. Verify the controller created managed Secrets:

   kubectl -n cert-manager get secret cloudflare -o json | jq -r '.metadata.annotations["sealedsecrets.bitnami.com/managed"]'
   kubectl -n external-dns get secret cloudflare -o json | jq -r '.metadata.annotations["sealedsecrets.bitnami.com/managed"]'

Tips:
- Use `--scope strict` to bind a secret to a specific namespace/name.
- For the same secret in multiple namespaces, prefer `--scope cluster-wide` and
  run the script with multiple `-n` flags; it will produce one file per namespace.

### Networking requirements

The server must load the `br_netfilter` and `overlay` kernel modules,
enable bridge firewalling and allow IPv4 forwarding so the bundled flannel CNI
works correctly.  This is handled in `hosts/nandstorm/default.nix` but is worth
noting when porting the configuration to other machines.
