{ config, pkgs, lib, ... }:

let
  nvidiaPackage = config.boot.kernelPackages.nvidiaPackages.legacy_580;
in
with config.boot.kernelPackages; {

  environment.systemPackages = [
    pkgs.cudatoolkit
    nvidiaPackage
  ];

  boot = {
    blacklistedKernelModules = ["nouveau"];
    kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
  };

  #virtualization.docker.enableNvidia = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    # Titan V is supported by the proprietary 580.xx legacy driver.
    package = nvidiaPackage;
    open = false;
    modesetting = { enable = true; };
  };

  # A kernel update cannot load its matching NVIDIA module until reboot.
  # Skip CDI generation during that interim rather than failing activation.
  systemd.services.nvidia-container-toolkit-cdi-generator.serviceConfig.ExecCondition =
    lib.getExe' nvidiaPackage "nvidia-smi";

}
