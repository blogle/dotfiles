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
    #./build-servers.nix
  ];


  time.timeZone = "America/Chicago";

  networking = {
    hostName = "modulus";
    networkmanager.enable = true;
  };

  environment.systemPackages = [
    config.boot.kernelPackages.perf
  ];

  boot = {
    initrd.luks.devices.crypted.device = "/dev/disk/by-uuid/167d5984-df64-4fa5-a435-2352615b3062";
    loader = {
      efi.canTouchEfiVariables = true;
      grub.enableCryptodisk = true;
      systemd-boot.enable = true;
    };

    kernelPackages = pkgs.linuxPackages_latest;

  };


  services.openssh = {
      enable = true;
      passwordAuthentication = true;
  };
  services.sshd.enable = true;
  system.stateVersion = lib.mkForce "21.05";
}
