{ config, lib, ... }:

let
  # Copy of the *current* k3s-generated containerd config with CDI enabled.
  # k3s reads /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl (if present)
  # and renders it into config.toml at startup.
  containerdConfigTemplate = ''
    # Managed by NixOS. k3s renders this into config.toml.
    version = 3
    root = "/var/lib/rancher/k3s/agent/containerd"
    state = "/run/k3s/containerd"

    [grpc]
      address = "/run/k3s/containerd/containerd.sock"

    [plugins.'io.containerd.internal.v1.opt']
      path = "/var/lib/rancher/k3s/agent/containerd"

    [plugins.'io.containerd.grpc.v1.cri']
      stream_server_address = "127.0.0.1"
      stream_server_port = "10010"

    [plugins.'io.containerd.cri.v1.runtime']
      enable_selinux = false
      enable_unprivileged_ports = true
      enable_unprivileged_icmp = true
      device_ownership_from_security_context = false
      enable_cdi = true
      cdi_spec_dirs = ["/etc/cdi", "/var/run/cdi"]

    [plugins.'io.containerd.cri.v1.images']
      snapshotter = "overlayfs"
      disable_snapshot_annotations = true
      use_local_image_pull = true

    [plugins.'io.containerd.cri.v1.images'.pinned_images]
      sandbox = "rancher/mirrored-pause:3.6"

    [plugins.'io.containerd.cri.v1.runtime'.cni]
      bin_dirs = ["/var/lib/rancher/k3s/data/cni"]
      conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d"

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
      SystemdCgroup = true

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runhcs-wcow-process]
      runtime_type = "io.containerd.runhcs.v1"

    [plugins.'io.containerd.cri.v1.images'.registry]
      config_path = "/var/lib/rancher/k3s/agent/etc/containerd/certs.d"
  '';

in
{
  environment.etc."rancher/k3s/containerd/config.toml.tmpl".text = containerdConfigTemplate;

  # Ensure k3s finds a template at its canonical path.
  systemd.tmpfiles.rules = [
    "L+ /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl - - - - /etc/rancher/k3s/containerd/config.toml.tmpl"
  ];
}
