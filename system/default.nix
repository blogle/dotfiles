{ system ? builtins.currentSystem, configuration ? ./configuration.nix }:

let pkgs = import ../nixpkgs.nix {
  config = { allowUnfree = true; };
};

in pkgs.nixos (import configuration)
