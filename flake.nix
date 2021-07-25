{
  description = "NixOS system configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    master.url = "github:NixOS/nixpkgs";

    fu.url = "github:numtide/flake-utils";
    utils = {
      url = "github:gytis-ivaskevicius/flake-utils-plus/staging";
      inputs.flake-utils.follows = "fu";
    };

    # flakes
    agenix.url = "github:ryantm/agenix";
    hm = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, utils, nixpkgs, hm, ... }@inputs:
    utils.lib.systemFlake {
      inherit self inputs;

      supportedSystems = [ "x86_64-linux" ];
      channelsConfig = { allowUnfree = true; };

      # modules and hosts

      hostDefaults = {
        modules = [
          utils.nixosModules.saneFlakeDefaults
        ];
      };

      hosts = {
        exclusivor = {
          modules = [ ./hosts/exclusivor ];
        };
      };

      # homes

      homeConfigurations = {

        home = hm.lib.homeManagerConfiguration {
          username = "ogle";
          homeDirectory = "/home/ogle";
          system = "x86_64-linux";
          #extraSpecialArgs = { inherit inputs; };

          configuration = {
            imports = [ ./home ];
            nixpkgs = {
              config = { allowUnfree = true; };
              overlays = [ self.overlay ];
            };
          };

        };

      };

      # overlays
      channels.nixpkgs.overlaysBuilder = channels: [
        self.overlay
      ];
      
      overlay = import ./pkgs;
      overlays = utils.lib.exportOverlays {
        inherit (self) pkgs inputs;
      };

      # packages
      outputsBuilder = channels: {
        packages = utils.lib.exportPackages self.overlays channels;
      };

	  devShellBuilder = channels:
		with channels.nixpkgs;
		mkShell {
          buildInputs = [
            hm.packages.x86_64-linux.home-manager
			#cachix
			#nixpkgs-fmt
			#nixos-generators
			#deploy-rs
		  ];
		};

    };

  #nixConfig = {
  #  substituters = [ "https://app.cachix.org/cache/fufexan" ];
  #  trusted-public-keys = [ "fufexan.cachix.org-1:LwCDjCJNJQf5XD2BV+yamQIMZfcKWR9ISIFy5curUsY=" ];
  #};
}
