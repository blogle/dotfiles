{ config, lib, pkgs, ... }:

with lib;

let
  mkService = name: secret:
    let
      dataArgs = concatStringsSep " " (mapAttrsToList (k: v:
        "--from-literal=" + k + "=\"$(cat " + toString v + ")\"") secret.data);
    in
    nameValuePair "k8s-secret-${name}" {
      description = "Apply Kubernetes secret ${name}";
      after = [ "k3s.service" "run-agenix.d.mount" ];
      wants = [ "k3s.service" "run-agenix.d.mount" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.k3s}/bin/k3s kubectl create secret generic ${name} \
          --namespace ${secret.namespace} \
          ${dataArgs} \
          --dry-run=client -o yaml | ${pkgs.k3s}/bin/k3s kubectl apply -f -
      '';
      wantedBy = [ "multi-user.target" ];
    };

in {
  options.kubeSecrets = mkOption {
    type = types.attrsOf (types.submodule ({ ... }: {
      options = {
        namespace = mkOption {
          type = types.str;
          default = "default";
        };
        data = mkOption {
          type = types.attrsOf types.path;
        };
      };
    }));
    default = {};
    description = "Secrets to create in Kubernetes";
  };

  config.systemd.services = mkMerge (mapAttrsToList mkService config.kubeSecrets);
}
