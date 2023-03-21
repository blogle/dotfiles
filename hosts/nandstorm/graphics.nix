{ config, pkgs, ... }:

with config.boot.kernelPackages; {
  
  environment.systemPackages = [ 
    pkgs.cudatoolkit
    nvidia_x11_production
  ];

  boot = {
    blacklistedKernelModules = ["nouveau"];
    extraModulePackages = [ nvidia_x11_production ];
  };

  #virtualization.docker.enableNvidia = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.opengl = {
    enable = true;
    driSupport32Bit = true;
  };

  hardware.nvidia = {
    modesetting = { enable = true; };
  };

}
