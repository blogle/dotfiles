{ config, pkgs, ... }:
{

  imports = [
    ./hardware-configuration.nix
    ./graphics.nix
    ./virtualization.nix
    ./build-servers.nix
  ];


  time.timeZone = "America/Chicago";

  networking = {
    hostName = "exclusivor";
    networkmanager.enable = true;
  };

  boot = {
    initrd.luks.devices.crypted.device = "/dev/disk/by-uuid/276700af-63cf-49bf-9d53-96cb0d5fa068";
    loader = {
      efi.canTouchEfiVariables = true;
      grub.enableCryptodisk = true;
      systemd-boot.enable = true;
    };

  };


}
