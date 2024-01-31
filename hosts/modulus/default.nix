{ config, lib, pkgs, ... }:

{

  imports = [
    ./hardware-configuration.nix
    ./users.nix
    ./fonts.nix
    ./graphics.nix
    ./virtualization.nix
    ./desktop.nix
    #./build-servers.nix
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

  # Enable perf in the kernel
  environment.systemPackages = [
    config.boot.kernelPackages.perf
  ];

  networking = {
    hostName = "modulus";
    timeServers = ["time.google.com"] ;
    networkmanager.enable = true;

    firewall = {
      enable = true;

      # Trust tailscale traffic
      trustedInterfaces = ["tailscale0"];

      # Allow the tailscale port
      allowedUDPPorts = [ config.services.tailscale.port ];

      # tailscale traffic will not match the same interface
      # on the opposite end - dont want to block this traffic
      checkReversePath = "loose";
    };

  };

  # Time/Locale
  time.timeZone = "America/Los_Angeles";

  # Enable ntp daemon
  services.chrony.enable = true;

  # Enable tailscale
  services.tailscale = { enable = true; };

  # Enable ssh
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
    };
  };

  services.sshd.enable = true;

  # Nix system version
  system.stateVersion = lib.mkForce "23.11";
}
