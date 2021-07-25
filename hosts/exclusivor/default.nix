{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  #age.secrets = {
  #  vaultwarden.file = ../../secrets/vaultwarden.age;
  #  ddclientConfig.file = ../../secrets/ddclientConfig.age;
  #  mailPass.file = ../../secrets/mailPass.age;
  #};
  boot = {
    initrd.luks.devices.crypted.device = "/dev/disk/by-uuid/276700af-63cf-49bf-9d53-96cb0d5fa068";
    loader = {
      efi.canTouchEfiVariables = true;
      grub.enableCryptodisk = true;
      systemd-boot.enable = true;
    };

  };

  # network
  networking = {
    hostName = "exclusivor";
    networkmanager.enable = true;
    #interfaces.enp9s0.useDHCP = true;
  };

  services = {
    # don't suspend when lid is closed
    # logind.lidSwitch = "ignore";

    # keep journal
    # journald.extraConfig = lib.mkForce "";
  };

  #users.users = {
  #  user.isSystemUser = true;
  #};

  system.stateVersion = lib.mkForce "21.05";
}
