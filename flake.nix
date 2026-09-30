{
  description = "NixOS system configurations";

  inputs = {
    sdlc.url = "github:blogle/sdlc/v1.1.1";
    nixpkgs.follows = "sdlc/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    anvil = {
      url = "github:blogle/anvil";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bubblebox = {
      url = "github:blogle/bubblebox";
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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opencode = {
      url = "github:anomalyco/opencode/v1.18.30";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
  };

  outputs = { self, nixpkgs, agenix, hm, impermanence, nixos-hardware, sdlc, ... }@inputs:
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
          anvilctl = inputs.anvil.packages.${final.system}.anvilctl;
          chatgpt = inputs.llm-agents.packages.${final.system}.chatgpt;
          home-manager = inputs.hm.packages.${final.system}.home-manager;
          # Temporary upstream hash correction for OpenCode v1.18.30.
          opencode = inputs.opencode.packages.${system}.default.override {
            node_modules = inputs.opencode.packages.${system}.node_modules_updater.override {
              hash = "sha256-F1ygMH30D/a/T8SaUuY69+LjBGnkHNLmQTvvrsz6NQA=";
            };
          };
        })
      ];

      hostOverlays = commonOverlays ++ [
        (final: prev: {
          agenix = agenix.packages.${final.system}.default;
        })
      ];

      homePkgs = import nixpkgs {
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

    hydraJobs.${system} = (sdlc.lib.mkConsumer {
      contract = import ./ci.nix { inherit self system; };
    }).hydraJobs;

    packages.${system} = {
      nix-eval-jobs = nixpkgs.legacyPackages.${system}.nix-eval-jobs;
      mergify-cli = sdlc.packages.${system}.mergify-cli;
      sdlc = sdlc.packages.${system}.sdlc;
    };

    apps.${system} = {
      sdlc = {
        type = "app";
        program = "${sdlc.packages.${system}.sdlc}/bin/sdlc";
      };
      nix-eval-jobs = {
        type = "app";
        program = "${nixpkgs.legacyPackages.${system}.nix-eval-jobs}/bin/nix-eval-jobs";
      };
      mergify-cli = {
        type = "app";
        program = "${sdlc.packages.${system}.mergify-cli}/bin/mergify";
      };
    };

    devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
      packages = sdlc.lib.devTools {
        pkgs = nixpkgs.legacyPackages.${system};
        sdlcCli = sdlc.packages.${system}.sdlc;
      } ++ [
        nixpkgs.legacyPackages.${system}.just
        nixpkgs.legacyPackages.${system}.jq
        nixpkgs.legacyPackages.${system}.nix-eval-jobs
        nixpkgs.legacyPackages.${system}.helm
        nixpkgs.legacyPackages.${system}.kubectl
        nixpkgs.legacyPackages.${system}.kustomize
        (nixpkgs.legacyPackages.${system}.python3.withPackages (pythonPackages: [
          pythonPackages.json5
          pythonPackages.pyyaml
        ]))
        nixpkgs.legacyPackages.${system}.docker-compose
        nixpkgs.legacyPackages.${system}.bun
        nixpkgs.legacyPackages.${system}.nodejs
      ];
    };

  };

}
