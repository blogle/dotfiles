{ config, pkgs, lib, ... }:
{

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
    extraFlags = [
      "--disable servicelb"
      "--disable-network-policy"
      "--disable local-storage"
      "--node-label=openebs.io/nodeid=nandstorm"
      "--write-kubeconfig-mode=644"
      "--flannel-iface=eno1"
      # Node-local container-log rotation. Caps each container's logs at
      # ~15MiB (5MiB max file * 3 files) so a chatty pod cannot fill the
      # node filesystem before Loki collects them. These knob names mirror
      # the kubelet flags `--container-log-max-size` / `--container-log-max-files`.
      # See docs/observability.md "Disk safety and retention".
      # Follow-up: k3s `--kubelet-arg` forwards these to the kubelet; a k3s
      # restart is required to pick them up (`systemctl restart k3s`).
      "--kubelet-arg=container-log-max-size=5Mi"
      "--kubelet-arg=container-log-max-files=3"
    ];
  };

  # k3s has been observed to crash-loop after unclean power loss,
  # failing during network policy initialization before the node has
  # fully settled its primary interface state.
  systemd.services.k3s = {
    after = [ "NetworkManager-wait-online.service" "systemd-time-wait-sync.service" "openebs-zfs-parent.service" ];
    wants = [ "NetworkManager-wait-online.service" "systemd-time-wait-sync.service" "openebs-zfs-parent.service" ];
    # The default KillMode=process leaves containerd shims holding the
    # persistent k3s mount open, preventing future NixOS activations.
    serviceConfig.KillMode = lib.mkForce "control-group";

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

  # OpenEBS ZFS LocalPV creates one child dataset per CSI volume below this
  # parent. Keep it outside k3s's own /var/lib/rancher state and create it
  # only when absent; this service never removes or rewrites existing data.
  systemd.services.openebs-zfs-parent = {
    description = "Create the OpenEBS ZFS LocalPV parent dataset";
    wantedBy = [ "multi-user.target" ];
    after = [ "persist.mount" ];
    requires = [ "persist.mount" ];
    path = [ pkgs.bash pkgs.zfs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      parent="rpool/safe/kubernetes"
      if ! zfs list -H -o name "$parent" >/dev/null 2>&1; then
        zfs create -p -o canmount=off -o mountpoint=none "$parent"
      fi
    '';
  };

  # Kubernetes secrets are now managed via Sealed Secrets manifests
  # in hosts/nandstorm/k8s. The previous kube-secrets module has been removed.

}
