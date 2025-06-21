{ config, pkgs, ... }:

{

  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
  };

  # Provide the NVIDIA runtime for Kubernetes workloads
  hardware.nvidia.containerToolkit.enable = true;

}
