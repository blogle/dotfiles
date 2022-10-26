{
  description = "NixOS system configurations";

  inputs = {
    master.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nur.url = "github:nix-community/nur";

    fu.url = "github:numtide/flake-utils";
    utils = {
      url = "github:gytis-ivaskevicius/flake-utils-plus/master";
      inputs.flake-utils.follows = "fu";
    };

    # flakes
    agenix.url = "github:ryantm/agenix";
    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "fu";
      };
    };

  };

  outputs = { self, utils, nixpkgs, hm, nixos-hardware, ... }@inputs:
    utils.lib.mkFlake rec {
      inherit self inputs;

      # overlays
      overlay = import ./pkgs;
      channelsConfig = {
        allowUnfree = true;
      };

      channels.nixpkgs = {
        input = nixpkgs;
        overlaysBuilder = _: [
          self.overlay
          inputs.nur.overlay
          inputs.rust-overlay.overlays.default

          (final: prev: {
            # Overwrites specified packages to be used from unstable channel.
            home-manager = inputs.hm.packages.x86_64-linux.home-manager;
            inherit (channels.master) ffmpeg-full;
          })
        ];
      };

      # modules and hosts

      hostDefaults = {
        modules = [
          #utils.nixosModules.saneFlakeDefaults
        ];
      };

      hosts = {
        exclusivor = {
          modules = [ ./hosts/exclusivor ];
        };

        modulus = {
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
            ./hosts/modulus
          ];
        };
      };

      # homes

      homeConfigurations = {

        home = hm.lib.homeManagerConfiguration {
          pkgs = self.pkgs.x86_64-linux.nixpkgs;
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

          extraSpecialArgs = { inherit inputs; };
        };

      };

      outputsBuilder = channels: {
        devShell =
        with channels.nixpkgs;
        mkShell {
          buildInputs = [
            home-manager
            ];
          };
        };
    };

  #nixConfig = {
  #  substituters = [ "https://app.cachix.org/cache/fufexan" ];
  #  trusted-public-keys = [ "fufexan.cachix.org-1:LwCDjCJNJQf5XD2BV+yamQIMZfcKWR9ISIFy5curUsY=" ];
  #};
}
