# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports = [
    ./graphics.nix
    ./virtualization.nix
  ];

  networking = {
    hostName = "cacheflow";
    nameservers = [ "8.8.8.8" "8.8.4.4"];
    timeServers = ["time.google.com"] ;

    firewall = {
      enable = true;

      # Trust tailscale traffic
      trustedInterfaces = ["tailscale0"];

      # Allow the tailscale port
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];

      # tailscale traffic will not match the same interface
      # on the opposite end - dont want to block this traffic
      checkReversePath = "loose";
    };

  };

  users.users.ogle = {
    name = "ogle";
    group = "users";
    extraGroups = [ "wheel" "docker" ];
    createHome = true;
    home = "/home/ogle";
    uid = 1000;
    isNormalUser = true;
    packages = with pkgs; [
      vim
      google-cloud-sdk
    ];

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDMbxQQ6asa917aD8HTavEinmIEsm6G3pZEOv7Rf33JCvvrdCW5ktOsjBm0oeRLt3aeC0QZa3nrMXixP7GCmJQWFPnAsQLlrpZnNRte5GB9X0wcUTUcvLo1kXzTBB5CRhSwdVQ9+/Ztc+LSiObPqFfsYY2pa85wYU6Q+Hu+aYSDrTvCzcL1ojEvUKnOmSWFYQ+fmYV7skKJL3Xr66zpWeCKyVtY8h7Ju3H3IWZTTl8Fyqtej63uHxqjQlMNzEjUL9Nzmev+O8+lCKvHXG+8dQBAYe3+tsIi1NKLSODSKxLpka52XIiNrgGnnr74YTZ8sp8Sd9STr3HUPr7uNK5I8DSL brandon@standard.ai"
      ];
  };

  users.users.matt = {
    name = "matt";
    group = "users";
    extraGroups = [ "wheel" "docker" ];
    createHome = true;
    home = "/home/matt";
    uid = 1001;
    isNormalUser = true;
    packages = with pkgs; [
      google-cloud-sdk
    ];

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCUiAcZLZBZf3Ln/c3hjetg7V5T7lx5HEMnXn4+3+kgGN47biyfWIA9aX1sxw42BaAuET8aEmvBynouE76GenaLWjg/GgaRfYU0NGcwhjVSbYCE1Si+srievytP3diRNrtTfF/txcUo1OBH0IdNCkFzKe4KYFanU1/BlpNm7LAXCJn4dlvKJc+kbJPByo3XM/nKEpb4PV3MtdLNpG2hCxOmQCTzli6TRHa8jRabLUOGY/cOPKqoAhjUs3cW5MYbKMFPF2SPCLlE5Kn0iEKGEW/tmeiH7+nJhAqsvF1nJ1iYHWZ3PNLDf5//JJu4m3+heIkOMxptHd5M+rO9LhVDfkqCvz/pmKHOy2qYK6OXOmpGthJfMBXkzCSfQxhE3KUandnSmc3t7C4qRzXEepvvNMDPSaDD/J24X3kZYr4mSywBq/2FArTYmdITl4rpH6P0LgtuqEZbITv9gNOlxcdHanVSmt1YpgXrXwHsgDroOp0VXsIHOO9DowYer6dhyNoPJKM= matt@standard.ai"
    ];
  };

  users.mutableUsers = false;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable tailscale
  services.tailscale = { enable = true; };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11"; # Did you read the comment?

}

