{ system ? builtins.currentSystem, configuration ? ./configuration.nix }:

let pkgs = import ../nixpkgs.nix {};
in import "${pkgs.path}/nixos" {
  inherit system configuration;
}
