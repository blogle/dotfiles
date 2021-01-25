{ config, pkgs, ... }:
{
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
  ];

  environment.systemPackages = [
    pkgs.home-manager
  ];
}
