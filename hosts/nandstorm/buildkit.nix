{ config, pkgs, lib, ... }:

let
  buildkitPort = 8089;
  buildkitdToml = pkgs.writeText "buildkitd.toml" ''
    [worker.oci]
      enabled = false

    [worker.containerd]
      enabled = true
      address = "unix:///run/k3s/containerd/containerd.sock"
      namespace = "k8s.io"
      platforms = ["linux/amd64"]
  '';
in
{
  environment.systemPackages = with pkgs; [
    buildkit
    nerdctl
  ];

  systemd.services.buildkitd = {
    description = "BuildKit daemon (k3s containerd backend)";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.buildkit}/bin/buildkitd \
        --addr unix:///run/buildkit/buildkitd.sock \
        --addr tcp://0.0.0.0:${toString buildkitPort} \
        --config ${buildkitdToml}";
      Restart = "always";
      RestartSec = 5;
      StateDirectory = "buildkit";
      RuntimeDirectory = "buildkit";
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/buildkit 0755 root root -"
  ];
}
