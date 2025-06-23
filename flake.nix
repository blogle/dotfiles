{
  description = "NixOS system configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, agenix, hm, nixos-hardware, impermanence, ... }@inputs:
    let
      system = "x86_64-linux";

      pkgConfig = {
        inherit system;
        config = {
          allowUnfree = true;
          allowBroken = true;
        };

        overlays = [
          inputs.nur.overlay
          inputs.rust-overlay.overlays.default
          (import ./pkgs)
          (final: prev: {
            agenix = agenix.packages.x86_64-linux.default;
            home-manager = inputs.hm.packages.x86_64-linux.home-manager;
          })
        ];
      };

      pkgs = import nixpkgs pkgConfig;
      nixpkgModule = {pkgs, ...}: {
        # Use our overlayed package set
        nixpkgs.config = pkgConfig.config;
        nixpkgs.overlays = pkgConfig.overlays;
        # Enable nix 2.0 api and flakes
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
      };

      # Module to support gce virtualization
      gceModule = {modulesPath, ...}: {
        imports = [
          "${toString modulesPath}/virtualisation/google-compute-image.nix"
        ];
      };

    in
  {

    legacyPackages."${system}" = pkgs;

    homeConfigurations = {
      home = hm.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home
          {
            home = {
              username = "ogle";
              homeDirectory = "/home/ogle";
              stateVersion = "22.05";
            };
          }
        ];
      };
    };

    nixosConfigurations = {

      modulus = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixpkgModule
          nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
          agenix.nixosModules.default
          ./hosts/modulus
        ];
      };

      nandstorm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixpkgModule
          agenix.nixosModules.default
          impermanence.nixosModules.impermanence
          ./hosts/nandstorm
        ];
      };

    };

    # Remote deploy-rs targets
    deploy.nodes = {
      nandstorm = {
        hostname = "10.0.0.15";
        profiles.system = {
          sshUser = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nandstorm;
        };
      };
    };

    # Validate system configs before shipping them off with deploy-rs
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;

  };

}
