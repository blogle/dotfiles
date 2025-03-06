{ config, pkgs, ... }:

{

  boot.kernelParams = [ "intel_iommu=on" "iommu=pt"];

  virtualisation.docker = {
    enable = true;
  };

  virtualisation.libvirtd = {
    enable = true;
  };

  virtualisation.virtualbox = {
    host = {
      enable = true;
      enableExtensionPack = true;
    };
  };

}
