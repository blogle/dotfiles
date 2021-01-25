{ config ? {}, overlays ? []}:
let 
  sources = import ./nix/sources.nix;
  packageOverlay = import ./packages.nix;
in 
  import sources.nixpkgs {
    inherit config;
    overlays = overlays ++ [ packageOverlay ];
  }
