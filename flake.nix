{
  description = "NixOS system configurations";

  inputs = {
    nixpkgs-home.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-modulus.url = "github:NixOS/nixpkgs/d0fcbf27c60bc66cf1f6236cfc3c5e9ac782786d";
    nixpkgs-nandstorm.url = "github:NixOS/nixpkgs/d0fcbf27c60bc66cf1f6236cfc3c5e9ac782786d";
    nixpkgs-tools.url = "github:NixOS/nixpkgs/d0fcbf27c60bc66cf1f6236cfc3c5e9ac782786d";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs-tools";
    };

    bubblebox = {
      url = "github:blogle/bubblebox";
      inputs.nixpkgs.follows = "nixpkgs-home";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs-tools";
    };

    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-home";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs-home";
    };
    
  };

  outputs = { self, nixpkgs-home, nixpkgs-modulus, nixpkgs-nandstorm, agenix, hm, impermanence, nixos-hardware, ... }@inputs:
    let
      system = "x86_64-linux";

      commonConfig = {
        allowUnfree = true;
        allowBroken = true;
      };

      commonOverlays = [
        inputs.nur.overlays.default
        (import ./pkgs)
      ];

      homeOverlays = commonOverlays ++ [
        inputs.bubblebox.overlays.default
        inputs.rust-overlay.overlays.default
        (final: prev: {
          agenix = agenix.packages.${final.system}.default;
          home-manager = inputs.hm.packages.${final.system}.home-manager;
        })
      ];

      hostOverlays = commonOverlays ++ [
        (final: prev: {
          agenix = agenix.packages.${final.system}.default;
        })
      ];

      homePkgs = import nixpkgs-home {
        inherit system;
        config = {
          inherit (commonConfig) allowUnfree allowBroken;
        };
        overlays = homeOverlays;
      };

      nixpkgModule = { ... }: {
        # Use our overlayed package set
        nixpkgs.config = commonConfig;
        nixpkgs.overlays = hostOverlays;
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

    legacyPackages."${system}" = homePkgs;

    homeConfigurations = {
      home = hm.lib.homeManagerConfiguration {
        pkgs = homePkgs;
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

      modulus = nixpkgs-modulus.lib.nixosSystem {
        inherit system;
        modules = [
          nixpkgModule
          nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
          agenix.nixosModules.default
          ./hosts/modulus
        ];
      };

      nandstorm = nixpkgs-nandstorm.lib.nixosSystem {
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
        hostname = "nandstorm";
        profiles.system = {
          sshUser = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.nandstorm;
        };
      };
    };

    # Validate system configs before shipping them off with deploy-rs
    # The configurations and deployment target in this flake are Linux-only.
    # Avoid evaluating deploy-rs checks for unsupported Darwin package sets.
    checks = {
      "${system}" = inputs.deploy-rs.lib.${system}.deployChecks self.deploy;
    };

  };

}
