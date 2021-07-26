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
      
      # overlays
      
      overlay = import ./pkgs;
      channelsConfig = { 
        allowUnfree = true;
      };

      sharedOverlays = [
        self.overlay
      ];

      channels.nixpkgs.input = nixpkgs;
 
      # Channel specific overlays
      channels.nixpkgs.overlaysBuilder = channels: [
        (final: prev: {
          # Overwrites specified packages to be used from unstable channel.
          home-manager = inputs.hm.packages.x86_64-linux.home-manager;
        })
      ];


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
          extraSpecialArgs = { inherit inputs; };

          configuration = {
            imports = [ ./home ];
            nixpkgs = {
              config = { allowUnfree = true; };
              overlays = [ self.overlay ];
            };
          };

        };

      };

      devShellBuilder = channels:
      with channels.nixpkgs;
      mkShell {
        buildInputs = [
          home-manager
          ];
        };

    };

  #nixConfig = {
  #  substituters = [ "https://app.cachix.org/cache/fufexan" ];
  #  trusted-public-keys = [ "fufexan.cachix.org-1:LwCDjCJNJQf5XD2BV+yamQIMZfcKWR9ISIFy5curUsY=" ];
  #};
}
