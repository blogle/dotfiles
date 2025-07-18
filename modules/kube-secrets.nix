{ config, lib, pkgs, ... }:

with lib;

let
  mkService = secretName: secret:
    let
      dataArgs = concatStringsSep " " (mapAttrsToList (k: v:
        "--from-literal=" + k + "=\"$(cat " + toString v + ")\"") secret.data);
    in
    nameValuePair "k8s-secret-${secretName}" {
      description = "Apply Kubernetes secret ${secretName}";
      after = [ "k3s.service" "run-agenix.d.mount" ];
      wants = [ "k3s.service" "run-agenix.d.mount" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.k3s}/bin/k3s kubectl create secret generic ${secretName} \
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

  config.systemd.services = lib.mergeAttrsList (mapAttrsToList (secretName: secret: {
    "k8s-secret-${secretName}" = {
      description = "Apply Kubernetes secret ${secretName}";
      after = [ "k3s.service" "run-agenix.d.mount" ];
      wants = [ "k3s.service" "run-agenix.d.mount" ];
      serviceConfig.Type = "oneshot";
      script = ''
        export PATH=${lib.makeBinPath [ pkgs.k3s ]}:$PATH
        ${pkgs.k3s}/bin/k3s kubectl create secret generic ${secretName} \
          --namespace ${secret.namespace} \
          ${concatStringsSep " " (mapAttrsToList (k: v: "--from-literal=" + k + "=\"$(cat " + toString v + ")\"") secret.data)} \
          --dry-run=client -o yaml | ${pkgs.k3s}/bin/kubectl apply -f -
      '';
      wantedBy = [ "multi-user.target" ];
    };
  }) config.kubeSecrets);
}
