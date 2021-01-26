{ config, pkgs, ... }:
let
  sources = import ../nix/sources.nix;
in
{


  imports = [ "${sources.home-manager}/nixos" ];

  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=${./configuration.nix}"
  ];

  environment.systemPackages = [
    pkgs.home-manager
  ];

  #home-manager.useGlobalPkgs = true;
  #home-manager.users.ogle = import /home/ogle/.config/nixpkgs/home.nix;
}
