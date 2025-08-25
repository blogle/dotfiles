{ config, pkgs, lib, ... }:
{

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = [
      "--disable servicelb"
      "--write-kubeconfig-mode=644"
    ];
  };

  # Kubernetes secrets are now managed via Sealed Secrets manifests
  # in hosts/nandstorm/k8s. The previous kube-secrets module has been removed.

}
