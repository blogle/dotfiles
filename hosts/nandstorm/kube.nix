{ config, pkgs, lib, ... }:
{
  imports = [ ../../modules/kube-secrets.nix ];

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = ''
      --disable servicelb
      --disable traefik
      --write-kubeconfig-mode=644
    '';
  };

  # Cloudflare API token for Traefik and ExternalDNS
  age.secrets.cloudflare-api-token.file = ../../secrets/cloudflare-api-token.age;

  secrets.cloudflare = { token = config.age.secrets.cloudflare-api-token.path; };

  kubeSecrets.cloudflare = {
    namespace = "kube-system";
    data = config.secrets.cloudflare;
  };
}
