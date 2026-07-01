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
    after = [ "NetworkManager-wait-online.service" "systemd-time-wait-sync.service" ];
    wants = [ "NetworkManager-wait-online.service" "systemd-time-wait-sync.service" ];

    preStart = ''
      set -euo pipefail

      iface="eno1"
      tries=120

      for _i in $(${pkgs.coreutils}/bin/seq 1 "$tries"); do
        if ${pkgs.iproute2}/bin/ip -4 -o addr show dev "$iface" | ${pkgs.gnugrep}/bin/grep -q " inet "; then
          # Verify gateway reachability to ensure network is fully settled
          gateway=$(${pkgs.iproute2}/bin/ip route show default dev "$iface" | ${pkgs.gnugrep}/bin/grep -oP 'via \K[\d.]+' | head -1)
          if [ -n "$gateway" ]; then
            if ${pkgs.iputils}/bin/ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
              exit 0
            fi
          else
            exit 0
          fi
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
