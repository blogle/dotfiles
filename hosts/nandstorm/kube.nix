{ config, pkgs, lib, ... }:
{

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = [
      "--disable servicelb"
      "--disable-network-policy"
      "--write-kubeconfig-mode=644"
      "--flannel-iface=eno1"
    ];
  };

  # k3s has been observed to crash-loop after unclean power loss,
  # failing during network policy initialization before the node has
  # fully settled its primary interface state.
  systemd.services.k3s = {
    after = [ "dhcpcd.service" "systemd-time-wait-sync.service" ];
    wants = [ "dhcpcd.service" "systemd-time-wait-sync.service" ];

    preStart = ''
      set -euo pipefail

      iface="eno1"
      tries=90

      for _i in $(${pkgs.coreutils}/bin/seq 1 "$tries"); do
        if ${pkgs.iproute2}/bin/ip -4 -o addr show dev "$iface" | ${pkgs.gnugrep}/bin/grep -q " inet "; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      echo "k3s: no IPv4 address on $iface after $tries""s" >&2
      exit 1
    '';
  };

  # Kubernetes secrets are now managed via Sealed Secrets manifests
  # in hosts/nandstorm/k8s. The previous kube-secrets module has been removed.

}
