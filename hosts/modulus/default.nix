{ config, lib, pkgs, ... }:

{

  #age.secrets = {
  #  vaultwarden.file = ../../secrets/vaultwarden.age;
  #  ddclientConfig.file = ../../secrets/ddclientConfig.age;
  #  mailPass.file = ../../secrets/mailPass.age;
  #};

  imports = [
    ./hardware-configuration.nix
    ./users.nix
    ./graphics.nix
    ./virtualization.nix
    ./desktop.nix
    ./build-servers.nix
  ];


  time.timeZone = "America/Chicago";

  networking = {
    hostName = "modulus";
    networkmanager.enable = true;
  };

  environment.systemPackages = [
    pkgs.linuxPackages.perf
  ];

  boot = {
    initrd.luks.devices.crypted.device = "/dev/disk/by-uuid/276700af-63cf-49bf-9d53-96cb0d5fa068";
    loader = {
      efi.canTouchEfiVariables = true;
      grub.enableCryptodisk = true;
      systemd-boot.enable = true;
    };

  };

  system.stateVersion = lib.mkForce "21.05";
}
