{ config, pkgs, lib, ... }:
{
  imports = [ ../../modules/kube-secrets.nix ];

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = [
      "--disable servicelb"
      "--write-kubeconfig-mode=644"
    ];
  };

  # Cloudflare API token for Traefik and ExternalDNS
  age.secrets.cloudflare-api-token.file = ../../secrets/cloudflare-api-token.age;

  # hmm - how do we want to handle secrets where the namespace is not provisioned yet.
  kubeSecrets.cloudflare = {
    namespace = "cert-manager";
    data = { api-key = config.age.secrets.cloudflare-api-token.path; };
  };

}
