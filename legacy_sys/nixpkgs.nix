{ config ? {}, overlays ? []}:
let
  sources = import ./nix/sources.nix;
  packageOverlay = import ./packages.nix;
  homeManager = import sources.home-manager {};
  homeManagerOverlay = self: super: {
    home-manager = homeManager.home-manager;
    home-manager-path = homeManager.path;
  };

in
  import sources.nixpkgs {
    inherit config;
    overlays = overlays ++ [
      homeManagerOverlay
      packageOverlay
    ];
  }
