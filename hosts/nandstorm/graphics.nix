{ config, pkgs, ... }:

with config.boot.kernelPackages; {

  environment.systemPackages = [
    pkgs.cudatoolkit
    nvidia_x11
  ];

  boot = {
    blacklistedKernelModules = ["nouveau"];
    extraModulePackages = [ nvidia_x11 ];
  };

  #virtualization.docker.enableNvidia = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    open = true;
    modesetting = { enable = true; };
  };

}
