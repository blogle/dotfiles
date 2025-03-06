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

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = false;
    package = nvidia_x11_production;
    modesetting = { enable = true; };
    prime.sync = { enable = true; };
  };

}
