{
  description = "NixOS system configurations";

  inputs = {
    sdlc.url = "github:blogle/sdlc/v2";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };

    anvil = {
      url = "github:blogle/anvil";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };

    bubblebox = {
      url = "github:blogle/bubblebox";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };

    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };

    impermanence = {
      url = "github:nix-community/impermanence";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };
    opencode = {
      url = "github:anomalyco/opencode/v1.18.35";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "sdlc/nixpkgs-latest";
    };
    
  };

  outputs = { self, agenix, hm, impermanence, nixos-hardware, sdlc, ... }@inputs:
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
          opencode = inputs.opencode.packages.${final.system}.opencode;
        })
      ];

      hostOverlays = commonOverlays ++ [
        (final: prev: {
          agenix = agenix.packages.${final.system}.default;
        })
      ];

      packageSets = sdlc.lib.importPackages {
        inherit system;
        latest = {
          config = commonConfig;
          overlays = homeOverlays;
        };
        stable = {
          config = commonConfig;
          overlays = hostOverlays;
        };
      };
      homePkgs = packageSets.latest;

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

      modulus = sdlc.nixpkgs-stable.lib.nixosSystem {
        inherit system;
        modules = [
          nixpkgModule
          nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
          agenix.nixosModules.default
          ./hosts/modulus
        ];
      };

      nandstorm = sdlc.nixpkgs-stable.lib.nixosSystem {
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

    ci.${system} = sdlc.lib.mkConsumer (import ./ci.nix {
      inherit self system;
      publish = sdlc.ci.${system}.publish;
    });

    packages.${system} = {
      nix-eval-jobs = packageSets.latest.nix-eval-jobs;
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
        program = "${packageSets.latest.nix-eval-jobs}/bin/nix-eval-jobs";
      };
      mergify-cli = {
        type = "app";
        program = "${sdlc.packages.${system}.mergify-cli}/bin/mergify";
      };
    };

    devShells.${system}.default = packageSets.latest.mkShell {
      packages = sdlc.lib.devTools {
        pkgs = packageSets.latest;
        sdlcCli = sdlc.packages.${system}.sdlc;
      } ++ [
        packageSets.latest.just
        packageSets.latest.jq
        packageSets.latest.nix-eval-jobs
        packageSets.latest.helm
        packageSets.latest.kubectl
        packageSets.latest.kubeseal
        packageSets.latest.kustomize
        packageSets.latest.openssl
        (packageSets.latest.python3.withPackages (pythonPackages: [
          pythonPackages.json5
          pythonPackages.pyyaml
        ]))
        packageSets.latest.docker-compose
        packageSets.latest.bun
        packageSets.latest.nodejs
      ];
    };

  };

}
