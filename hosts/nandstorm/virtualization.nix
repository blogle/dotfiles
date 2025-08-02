{ config, pkgs, ... }:

{

  virtualisation.docker = {
    enable = true;
    daemon.settings.features.cdi = true;
  };

  hardware.nvidia-container-toolkit.enable = true;

}
