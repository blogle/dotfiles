{
  description = "NixOS system configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Should look into using this flake for managing secrets
    # agenix.url = "github:ryantm/agenix";

    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, hm, nixos-hardware, ... }@inputs:
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
            # Overwrites specified packages to be used from unstable channel.
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
      exclusivor = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ 
          nixpkgModule
          ./hosts/exclusivor
        ];
      };

      modulus = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixpkgModule
          nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
          ./hosts/modulus
        ];
      };

      nandstorm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ 
          nixpkgModule
          ./hosts/nandstorm
        ];
      };

      cacheflow = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          gceModule
          nixpkgModule
          ./hosts/cacheflow
        ];
      };

    };

    # Export an artifact that we can use to create a compute-engine vm
    cacheflow-gce-image = self.nixosConfigurations.cacheflow.config.system.build.googleComputeImage;

    # Remote deploy-rs targets
    deploy.nodes = {
      nandstorm = {
        hostname = "192.168.1.20";
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
